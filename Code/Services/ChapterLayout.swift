//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import SwiftUI
import UIKit

/// One chapter, laid out for one style and one page size.
///
/// TextKit rather than CoreText, because CoreText does not hyphenate: it treats a soft hyphen as a place
/// it may break a word and then draws no hyphen there, which is worse than not breaking at all.
///
/// The chapter is laid out once as a single column and then cut into pages line by line, so the page
/// breaks can follow the rules a compositor would: no line of a paragraph left alone at either end of a
/// page, no hyphen at the foot of a page, no heading stranded without its text. The slack those rules
/// leave behind is spread between the lines of the page rather than dumped at the bottom.
@MainActor
final class ChapterLayout {
    /// How the pages of a chapter are laid out, before any text is fetched.
    ///
    /// A page fills the screen, so the text has to keep clear of the notch and the home indicator as
    /// well as of the reader's own margins.
    struct Context: Equatable {
        var style: ChapterTextStyle
        var margins: Double
        var pageSize: CGSize
        var safeArea: EdgeInsets

        /// The band kept at the top and bottom of every page for the book title and the page number.
        static let runningHeadHeight: CGFloat = 22

        /// Where the body text is laid out and drawn, in the page's own coordinates.
        var textRect: CGRect {
            CGRect(origin: .zero, size: pageSize).inset(by: UIEdgeInsets(
                top: safeArea.top + margins + Self.runningHeadHeight,
                left: safeArea.leading + margins,
                bottom: safeArea.bottom + margins + Self.runningHeadHeight,
                right: safeArea.trailing + margins
            ))
        }

        var textSize: CGSize { textRect.size }

        var isUsable: Bool { textRect.width > 1 && textRect.height > 1 }
    }

    /// What a compositor would not allow. Line counts, and the points a line gap may give or take.
    enum Rules {
        /// Lines that have to follow a heading rather than leaving it stranded at the foot of a page.
        static let linesAfterHeading = 2
        /// However hard the other rules push, a page keeps at least this many lines.
        static let minimumLines = 4
        /// How many lines a rule may move to the next page.
        static let pullBack = 4
        /// A last page shorter than this is fed from the page before it.
        static let shortLastPage = 3
        /// How far a line gap may be squeezed to pull one more line onto a page.
        static let tightening: CGFloat = 0.75
        /// How far a line gap may open to take up the slack a rule left behind.
        static let loosening: CGFloat = 3
    }

    /// Text longer than this is worth telling the reader about while it is being laid out.
    static let progressThreshold = 239 * 1024

    let chapterId: Int
    let context: Context

    /// What the previous chapter already used on this chapter's first page, when the chapter runs on
    /// from it rather than starting a page of its own.
    let startOffset: CGFloat

    /// The character range each page covers, so a reading position survives a change of font.
    private(set) var pageRanges: [NSRange] = []

    private let storage: NSTextStorage
    private let manager = NSLayoutManager()
    private let container: NSTextContainer
    private let headingLength: Int

    private var lines: [Line] = []
    private var pages: [Page] = []

    /// One laid-out line, and everything the page breaker needs to know about it.
    private struct Line {
        var glyphs: NSRange
        var characters: NSRange
        var columnTop: CGFloat
        var height: CGFloat
        var startsParagraph: Bool
        var endsParagraph: Bool
        /// The line breaks a word, so a hyphen is drawn at its end.
        var endsWithHyphen: Bool
        var isHeading: Bool
    }

    /// One page: the lines it carries and the space added to (or taken from) each gap between them.
    private struct Page {
        var lines: Range<Int>
        var leading: CGFloat
    }

    init(chapterId: Int, text: ChapterPagination.TypesetText, context: Context, startOffset: CGFloat = 0) {
        self.chapterId = chapterId
        self.context = context
        self.startOffset = max(0, startOffset)
        self.headingLength = text.headingLength
        self.storage = NSTextStorage(attributedString: text.attributed)
        self.container = NSTextContainer(size: CGSize(
            width: max(1, context.textSize.width),
            height: .greatestFiniteMagnitude
        ))
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 0
        manager.usesFontLeading = true
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
    }

    /// Lays a chapter out and cuts it into pages.
    ///
    /// TextKit is not thread-safe, so this stays on the main actor; it lays the column out in slices and
    /// yields between them, so a long chapter never blocks a page turn.
    static func make(
        chapterId: Int,
        content: ChapterContent,
        heading: ChapterHeading,
        context: Context,
        startOffset: CGFloat = 0,
        onProgress: (@MainActor (Double) -> Void)? = nil
    ) async -> ChapterLayout {
        let text = ChapterPagination.typeset(
            // Justified setting takes every break the dictionary offers; ragged-right needs no
            // filling, so it is set as it was written.
            paragraphs: context.style.justifies(content.language) ? content.hyphenated : content.paragraphs,
            heading: heading,
            language: content.language,
            style: context.style
        )
        let layout = ChapterLayout(chapterId: chapterId, text: text, context: context, startOffset: startOffset)
        await layout.build(onProgress: onProgress)
        return layout
    }

    /// True when laying this chapter out takes long enough that the reader should be told.
    var isLong: Bool { storage.string.utf8.count > Self.progressThreshold }

    private func build(onProgress: (@MainActor (Double) -> Void)?) async {
        guard context.isUsable, storage.length > 0 else { return }

        await layoutColumn(onProgress: isLong ? onProgress : nil)
        collectLines()
        composePages()
        pageRanges = pages.map { page in
            let first = lines[page.lines.lowerBound].characters
            let last = lines[page.lines.upperBound - 1].characters
            return NSRange(location: first.location, length: last.location + last.length - first.location)
        }
    }

    private func layoutColumn(onProgress: (@MainActor (Double) -> Void)?) async {
        let slice = max(context.textSize.height * 4, 400)
        let total = manager.numberOfGlyphs
        var columnTop: CGFloat = 0
        var laidOut = -1

        while manager.firstUnlaidGlyphIndex() < total {
            let bounds = CGRect(x: 0, y: columnTop, width: container.size.width, height: slice)
            manager.ensureLayout(forBoundingRect: bounds, in: container)

            let progress = manager.firstUnlaidGlyphIndex()

            guard progress > laidOut else { break }

            laidOut = progress
            columnTop += slice
            onProgress?(total > 0 ? Double(progress) / Double(total) : 1)
            await Task.yield()
        }

        onProgress?(1)
    }

    private func collectLines() {
        let string = storage.string as NSString
        let glyphs = NSRange(location: 0, length: manager.numberOfGlyphs)

        manager.enumerateLineFragments(forGlyphRange: glyphs) { _, usedRect, _, glyphRange, _ in
            let characters = self.manager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let ending = characters.location + characters.length

            self.lines.append(Line(
                glyphs: glyphRange,
                characters: characters,
                columnTop: usedRect.minY,
                height: usedRect.height,
                startsParagraph: characters.location == 0
                    || string.character(at: characters.location - 1) == 0x0A,
                endsParagraph: ending >= string.length || string.character(at: ending - 1) == 0x0A,
                endsWithHyphen: Self.breaksAWord(string, at: characters),
                isHeading: characters.location < self.headingLength
            ))
        }

        // `usedRect` gives each line its own height; a gap between two of them belongs to the line above.
        for index in lines.indices.dropLast() {
            lines[index].height = lines[index + 1].columnTop - lines[index].columnTop
        }
    }

    /// True when the line stops in the middle of a word, which is where TextKit draws its hyphen.
    private static func breaksAWord(_ string: NSString, at range: NSRange) -> Bool {
        let ending = range.location + range.length

        guard ending > 0, ending < string.length else { return false }

        // A line broken at a soft hyphen carries that hyphen, and the page rules count it as one.
        if string.character(at: ending - 1) == softHyphen { return true }

        let letters = CharacterSet.letters
        let before = Unicode.Scalar(string.character(at: ending - 1))
        let after = Unicode.Scalar(string.character(at: ending))

        guard let before, let after else { return false }

        return letters.contains(before) && letters.contains(after)
    }

    // MARK: - Cutting the column into pages

    private func composePages() {
        guard !lines.isEmpty else { return }

        var start = 0

        while start < lines.count {
            let available = height(ofPageAt: pages.count)
            let greedy = greedyBreak(from: start, available: available)
            let limit = observeRules(breakingAt: greedy, from: start)
            pages.append(Page(lines: start ..< limit, leading: 0))
            start = limit
        }

        feedShortLastPage()

        for index in pages.indices {
            pages[index].leading = leading(for: pages[index], available: height(ofPageAt: index))
        }
    }

    private func height(ofPageAt index: Int) -> CGFloat {
        context.textSize.height - (index == 0 ? startOffset : 0)
    }

    /// As many lines as fit, allowing the gaps to be squeezed a little to take one more.
    private func greedyBreak(from start: Int, available: CGFloat) -> Int {
        var limit = start
        var used: CGFloat = 0

        while limit < lines.count {
            let slack = CGFloat(max(0, limit - start)) * Rules.tightening
            let height = lines[limit].height

            guard used + height <= available + slack else { break }

            used += height
            limit += 1
        }

        return max(limit, start + 1)
    }

    /// Moves the break back off a line no compositor would leave where it fell.
    private func observeRules(breakingAt limit: Int, from start: Int) -> Int {
        var limit = limit
        var moved = 0

        while moved < Rules.pullBack, limit - start > Rules.minimumLines, limit < lines.count || moved == 0 {
            guard let better = violation(breakingAt: limit, from: start) else { break }
            guard better > start else { break }

            limit = better
            moved += 1
        }

        return limit
    }

    /// Where the break should move to, or `nil` when it is already in a decent place.
    private func violation(breakingAt limit: Int, from start: Int) -> Int? {
        let last = lines[limit - 1]
        let next = limit < lines.count ? lines[limit] : nil

        // A heading belongs with the text it introduces.
        if let strandedHeading = headingStranded(breakingAt: limit, from: start) { return strandedHeading }

        guard let next else { return nil }

        // A page cannot end on a broken word.
        if last.endsWithHyphen { return limit - 1 }

        // An orphan: the first line of a paragraph, alone at the foot of the page.
        if last.startsParagraph, !last.endsParagraph { return limit - 1 }

        // A widow: the last line of a paragraph, alone at the top of the next one.
        if next.endsParagraph, !next.startsParagraph { return limit - 1 }

        return nil
    }

    /// A heading, or a heading with too little text under it, has to move to the next page whole.
    private func headingStranded(breakingAt limit: Int, from start: Int) -> Int? {
        guard limit < lines.count else { return nil }

        let tail = max(start, limit - Rules.linesAfterHeading - 1) ..< limit

        guard let heading = tail.last(where: { lines[$0].isHeading }) else { return nil }
        guard limit - heading <= Rules.linesAfterHeading else { return nil }

        // Move to the first line of the heading block, so the whole heading travels together.
        var first = heading

        while first > start, lines[first - 1].isHeading { first -= 1 }

        return first > start ? first : nil
    }

    /// A chapter ending in a line or two on a page of its own reads as a mistake. The page before it
    /// gives up lines until the last one carries a decent piece of text.
    private func feedShortLastPage() {
        guard pages.count > 1 else { return }

        let last = pages.count - 1
        let lastCount = pages[last].lines.count

        guard lastCount < Rules.shortLastPage else { return }

        let previous = pages[last - 1].lines
        let spare = previous.count - Rules.minimumLines
        let wanted = Rules.shortLastPage + 1 - lastCount

        guard spare > 0 else { return }

        let moved = min(spare, wanted)
        pages[last - 1] = Page(lines: previous.lowerBound ..< (previous.upperBound - moved), leading: 0)
        pages[last] = Page(lines: (pages[last].lines.lowerBound - moved) ..< pages[last].lines.upperBound, leading: 0)
    }

    /// Spreads what is left of the page between its lines, so a rule that pushed a line away doesn't
    /// leave a hole at the foot of the page. A page that ends a chapter keeps its ragged bottom.
    private func leading(for page: Page, available: CGFloat) -> CGFloat {
        let gaps = page.lines.count - 1

        guard gaps > 0 else { return 0 }

        let used = page.lines.reduce(CGFloat(0)) { $0 + lines[$1].height }
        let slack = available - used

        guard slack != 0 else { return 0 }
        // A page left half empty is the end of the chapter, not a page break to hide.
        guard abs(slack) < lines[page.lines.lowerBound].height * 2 else { return 0 }

        return min(max(slack / CGFloat(gaps), -Rules.tightening), Rules.loosening)
    }

    // MARK: - What the reader asks for

    var pageCount: Int { pages.count }

    var isEmpty: Bool { pages.isEmpty }

    /// What is left on the last page, for deciding whether the next chapter can run on from here.
    var tailFreeSpace: CGFloat {
        guard let page = pages.last else { return 0 }

        let used = page.lines.reduce(CGFloat(0)) { $0 + lines[$1].height }
        return max(0, height(ofPageAt: pages.count - 1) - used)
    }

    /// The page a character offset falls on, so a change of font keeps the reader's place.
    func pageIndex(containing offset: Int) -> Int {
        let laidOut = laidOutOffset(offset)
        return pageRanges.firstIndex { NSLocationInRange(laidOut, $0) } ?? max(0, min(offset, pageCount - 1))
    }

    func characterOffset(ofPage index: Int) -> Int {
        pageRanges.indices.contains(index) ? sourceOffset(pageRanges[index].location) : 0
    }

    /// A position is counted in the text as it arrived, not in the text as it was set.
    ///
    /// Justified text carries a soft hyphen at every break the dictionary allows, roughly one character
    /// in eight. Counting those would move a stored position whenever the alignment changed, which is
    /// the one thing a stored position must never do.
    private func sourceOffset(_ laidOut: Int) -> Int {
        let string = storage.string as NSString
        var result = 0

        for index in 0 ..< min(laidOut, string.length) where string.character(at: index) != Self.softHyphen {
            result += 1
        }

        return result
    }

    private func laidOutOffset(_ source: Int) -> Int {
        let string = storage.string as NSString
        var remaining = source
        var index = 0

        while index < string.length, remaining > 0 {
            if string.character(at: index) != Self.softHyphen { remaining -= 1 }

            index += 1
        }

        return index
    }

    private static let softHyphen = unichar(0x00AD)

    /// Draws a page, line by line, so the page's own leading can be applied as it goes.
    func draw(page index: Int) {
        guard pages.indices.contains(index) else { return }

        let page = pages[index]
        var cursor = context.textRect.minY + (index == 0 ? startOffset : 0)

        for line in page.lines {
            let origin = CGPoint(x: context.textRect.minX, y: cursor - lines[line].columnTop)
            manager.drawGlyphs(forGlyphRange: lines[line].glyphs, at: origin)
            cursor += lines[line].height + page.leading
        }
    }

    /// The page's text, for VoiceOver and for the reader's own accessibility label.
    func pageText(_ index: Int) -> String {
        guard pageRanges.indices.contains(index) else { return "" }

        // Without stripping them, VoiceOver reads a page full of soft hyphens.
        return (storage.string as NSString)
            .substring(with: pageRanges[index])
            .replacingOccurrences(of: String(Typography.softHyphen), with: "")
            .replacingOccurrences(of: "\u{2060}", with: "")
    }
}
