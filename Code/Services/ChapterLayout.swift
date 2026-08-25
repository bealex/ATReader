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

    /// What a compositor would not allow: line counts, the points a line gap may give or take, and what
    /// breaking a rule costs against letting a page come out the wrong depth.
    enum Rules {
        /// Lines that have to follow a heading rather than leaving it stranded at the foot of a page.
        static let linesAfterHeading = 2
        /// However hard the other rules push, a page keeps at least this many lines.
        static let minimumLines = 4
        /// A chapter's last page reads as a mistake with fewer lines than this.
        static let shortLastPage = 3
        /// How far a line gap may be squeezed to pull one more line onto a page.
        static let tightening: CGFloat = 0.75
        /// How far a line gap may open to take up the slack a rule left behind.
        static let loosening: CGFloat = 3
        /// What one broken rule costs. Far above any amount of uneven depth, so the rules still decide
        /// where a page may break and evenness only chooses between the breaks they allow.
        static let brokenRule: Double = 1000
        /// What each line a chapter's last page falls short of a decent ending costs.
        static let thinLastPage: Double = 40
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

        for limit in chooseBreaks() {
            pages.append(Page(lines: start ..< limit, leading: 0))
            start = limit
        }

        for index in pages.indices {
            pages[index].leading = leading(
                for: pages[index],
                available: height(ofPageAt: index),
                endsTheChapter: index == pages.count - 1
            )
        }
    }

    private func height(ofPageAt index: Int) -> CGFloat {
        context.textSize.height - (index == 0 ? startOffset : 0)
    }

    /// The depth of a page starting on a given line. Only a chapter's first page is ever short, and only
    /// where the chapter before it left it something.
    private func capacity(startingAt line: Int) -> CGFloat {
        context.textSize.height - (line == 0 ? startOffset : 0)
    }

    /// The depth of an ordinary line of the body, which is the unit a page's shortfall is counted in.
    private var referenceLineHeight: CGFloat {
        max(1, context.style.fontSize + context.style.lineSpacing)
    }

    /// Where every page of the chapter breaks, chosen so the pages come out the same depth.
    ///
    /// Filling each page in turn and handing whatever a rule rejects to the next one is what left a page
    /// four lines short between two full ones: wherever the rule bit, that page paid all of it. So every
    /// run of breaks is costed instead, a page's shortfall counted in lines and squared, and the cheapest
    /// run wins. Squaring is what shares the loss out, since one line missing from each of four pages
    /// costs a quarter of what four missing from one does.
    ///
    /// The rules are not traded against depth. Breaking one costs so much more than any unevenness that
    /// they still decide where a page may break, and evenness only chooses among the breaks they allow.
    private func chooseBreaks() -> [Int] {
        let count = lines.count
        var best = [Double](repeating: .infinity, count: count + 1)
        var next = [Int](repeating: count, count: count + 1)
        best[count] = 0

        for start in stride(from: count - 1, through: 0, by: -1) {
            let available = capacity(startingAt: start)
            var used: CGFloat = 0
            var limit = start + 1

            while limit <= count {
                used += lines[limit - 1].height
                let squeeze = CGFloat(limit - start - 1) * Rules.tightening

                // Nothing longer will fit. One line always may, so a line taller than the page still
                // lands on one instead of leaving the chapter with nowhere to break.
                if used > available + squeeze, limit > start + 1 { break }

                let total = cost(from: start, to: limit, available: available, used: used) + best[limit]

                if total < best[start] {
                    best[start] = total
                    next[start] = limit
                }

                limit += 1
            }
        }

        var breaks: [Int] = []
        var start = 0

        while start < count {
            let limit = next[start]

            guard limit > start else { break }

            breaks.append(limit)
            start = limit
        }

        return breaks
    }

    /// What one page costs: the rules it breaks, and how far short of its measure it comes.
    private func cost(from start: Int, to limit: Int, available: CGFloat, used: CGFloat) -> Double {
        let count = limit - start
        let endsTheChapter = limit == lines.count
        var penalty = Double(brokenRules(breakingAt: limit, from: start)) * Rules.brokenRule

        if count < Rules.minimumLines, !endsTheChapter { penalty += Rules.brokenRule }

        guard
            !endsTheChapter
        else {
            // A chapter ending in a line or two on a page of its own reads as a mistake, so the page
            // before it is worth shortening to feed it.
            return penalty + Double(max(0, Rules.shortLastPage + 1 - count)) * Rules.thinLastPage
        }

        let short = Double((available - used) / referenceLineHeight)
        return penalty + short * short
    }

    /// How many of a compositor's rules breaking here would break.
    private func brokenRules(breakingAt limit: Int, from start: Int) -> Int {
        // The end of the chapter is where the text stops, not a break that has to answer for itself.
        guard limit < lines.count else { return 0 }

        let last = lines[limit - 1]
        let following = lines[limit]
        var broken = 0

        // A page cannot end on a broken word.
        if last.endsWithHyphen { broken += 1 }

        // An orphan: the first line of a paragraph, alone at the foot of the page.
        if last.startsParagraph, !last.endsParagraph { broken += 1 }

        // A widow: the last line of a paragraph, alone at the top of the next one.
        if following.endsParagraph, !following.startsParagraph { broken += 1 }

        // A heading belongs with the text it introduces.
        if headingStranded(breakingAt: limit, from: start) { broken += 1 }

        return broken
    }

    /// True when the page ends on a heading, or with too little of its chapter under it.
    private func headingStranded(breakingAt limit: Int, from start: Int) -> Bool {
        let tail = max(start, limit - Rules.linesAfterHeading - 1) ..< limit

        guard let heading = tail.last(where: { lines[$0].isHeading }) else { return false }

        return limit - heading <= Rules.linesAfterHeading
    }

    /// Spreads what is left of the page between its lines, so every page comes down to the same depth
    /// instead of leaving the hole a rule made at its foot.
    ///
    /// A page that ends a chapter keeps its ragged bottom: it stops where the chapter stops, and opening
    /// its gaps would only put air between the last lines the reader sees.
    private func leading(for page: Page, available: CGFloat, endsTheChapter: Bool) -> CGFloat {
        let gaps = page.lines.count - 1

        guard gaps > 0, !endsTheChapter else { return 0 }

        let used = page.lines.reduce(CGFloat(0)) { $0 + lines[$1].height }
        let slack = available - used

        guard slack != 0 else { return 0 }

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
