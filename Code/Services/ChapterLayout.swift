//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import CoreText
import SwiftUI
import UIKit

/// One chapter, laid out for one style and one page size.
///
/// `ColumnComposer` sets the chapter as a single column, choosing every break in a paragraph together
/// with how each of its lines is filled. This cuts that column into pages line by line, so the page
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

        /// The band kept at the top and bottom of every page for the book title and the page number,
        /// which is as deep as the head drawn in it and no deeper.
        static let runningHeadHeight: CGFloat = 26

        /// Where the body text is laid out and drawn, in the page's own coordinates.
        var textRect: CGRect {
            CGRect(origin: .zero, size: pageSize).inset(by: UIEdgeInsets(
                // Half the margin above and below: the running head's own band already parts the text
                // from the edge, where the sides have nothing but the margin to do it.
                top: safeArea.top + margins / 2 + Self.runningHeadHeight,
                left: safeArea.leading + margins,
                bottom: safeArea.bottom + margins / 2 + Self.runningHeadHeight,
                right: safeArea.trailing + margins
            ))
        }

        var textSize: CGSize { textRect.size }

        var isUsable: Bool { textRect.width > 1 && textRect.height > 1 }

        /// Everything about the setting that moves where a line breaks, as one string.
        ///
        /// Measurements a book has already been through are kept against this, so a book reopened at
        /// the same settings costs a read rather than laying every chapter out again. The page's
        /// colours and how its pictures take them are deliberately absent: they change nothing about
        /// where anything sits, and including them would throw the whole book away every time the
        /// reader crossed into the dark.
        var fingerprint: String {
            [
                ChapterLayout.rulesVersion,
                style.face.rawValue,
                style.weight.rawValue,
                "\(style.fontSize)", "\(style.lineSpacing)", "\(style.letterSpacing)",
                "\(style.justifiesRussian)", "\(style.justifiesEnglish)",
                "\(margins)", "\(pageSize.width)x\(pageSize.height)",
                "\(safeArea.top),\(safeArea.leading),\(safeArea.bottom),\(safeArea.trailing)",
            ].joined(separator: "|")
        }
    }

    /// What a compositor would not allow: line counts, the points a line gap may give or take, and what
    /// breaking a rule costs against letting a page come out the wrong depth.
    /// Bumped whenever a rule here or in `ColumnComposer` changes where a line breaks or how far one is
    /// opened.
    ///
    /// Measurements are kept against the setting they were made at, and the setting alone says nothing
    /// about the rules that read it. Without this, changing how far a mark hangs would leave every book
    /// on the device showing the breaks an older layout chose.
    nonisolated static let rulesVersion = "11"

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

    private let text: NSAttributedString
    private let headingLength: Int

    private var lines: [ColumnComposer.Line] = []
    private var pages: [Page] = []

    /// One page: the lines it carries and the space added to (or taken from) each gap between them.
    private struct Page {
        var lines: Range<Int>
        var leading: CGFloat
        /// Air set above and below each picture on the page, which is what centres one in its space.
        var imagePadding: CGFloat = 0
    }

    init(chapterId: Int, text: ChapterPagination.TypesetText, context: Context, startOffset: CGFloat = 0) {
        self.chapterId = chapterId
        self.context = context
        self.startOffset = max(0, startOffset)
        self.headingLength = text.headingLength
        self.text = text.attributed
    }

    /// Lays a chapter out and cuts it into pages.
    ///
    /// CoreText is what measures and draws, but the setting is built from `UIFont` and drawn into a
    /// UIKit context, so this stays on the main actor and yields between paragraphs instead.
    static func make(
        chapterId: Int,
        content: ChapterContent,
        heading: ChapterHeading,
        context: Context,
        startOffset: CGFloat = 0,
        onProgress: (@MainActor (Double) -> Void)? = nil
    ) async -> ChapterLayout {
        // The pictures are read off the device before anything is measured: a line as deep as a plate
        // cannot be set without knowing how deep the plate is.
        let images = await BookImages.shared.prepare(sources: content.imageSources)
        let text = ChapterPagination.typeset(
            // Justified setting takes every break the dictionary offers; ragged-right needs no
            // filling, so it is set as it was written.
            paragraphs: context.style.justifies(content.language) ? content.hyphenated : content.paragraphs,
            heading: heading,
            language: content.language,
            style: context.style,
            images: images
        )
        let layout = ChapterLayout(chapterId: chapterId, text: text, context: context, startOffset: startOffset)
        await layout.build(onProgress: onProgress)
        return layout
    }

    /// True when laying this chapter out takes long enough that the reader should be told.
    var isLong: Bool { text.string.utf8.count > Self.progressThreshold }

    private func build(onProgress: (@MainActor (Double) -> Void)?) async {
        guard context.isUsable, text.length > 0 else { return }

        lines = await ColumnComposer.compose(
            text: text,
            headingLength: headingLength,
            measure: context.textSize.width,
            depth: context.textSize.height,
            onProgress: isLong ? onProgress : nil
        )
        composePages()
        pageRanges = pages.map { page in
            let first = lines[page.lines.lowerBound].characters
            let last = lines[page.lines.upperBound - 1].characters
            return NSRange(location: first.location, length: last.location + last.length - first.location)
        }
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
            let spread = spacing(
                for: pages[index],
                available: height(ofPageAt: index),
                endsTheChapter: index == pages.count - 1
            )

            pages[index].leading = spread.leading
            pages[index].imagePadding = spread.imagePadding
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
    /// Where a page's spare room goes: between its lines, and around the pictures standing on it.
    private struct Spacing {
        var leading: CGFloat = 0
        var imagePadding: CGFloat = 0
    }

    private func spacing(for page: Page, available: CGFloat, endsTheChapter: Bool) -> Spacing {
        let gaps = page.lines.count - 1
        let used = page.lines.reduce(CGFloat(0)) { $0 + lines[$1].height }
        let slack = available - used
        // A page that ends a chapter keeps its ragged bottom: the text stops where the chapter stops,
        // and opening its gaps would only put air between the last lines the reader sees. Everywhere
        // else the lines take their share first, so a page of text carrying a picture comes down to the
        // same depth as every other page.
        let leading =
            endsTheChapter || gaps <= 0
            ? 0
            : min(max(slack / CGFloat(gaps), -Rules.tightening), Rules.loosening)
        let pictures = picturesTakingTheRoom(on: page, endsTheChapter: endsTheChapter)

        guard pictures > 0, slack > 0 else { return Spacing(leading: leading) }

        // Whatever no amount of leading could absorb is the pictures'.
        return Spacing(leading: leading, imagePadding: (slack - leading * CGFloat(gaps)) / CGFloat(2 * pictures))
    }

    /// How many pictures share what the lines left behind.
    ///
    /// On a page that ends a chapter the spare room stands after the last line rather than being spread
    /// through the page, so only a picture at the end of one has any of that room under it to be
    /// centred in. A picture with the chapter's last words below it already sits where it belongs.
    private func picturesTakingTheRoom(on page: Page, endsTheChapter: Bool) -> Int {
        guard endsTheChapter else { return page.lines.count { lines[$0].image != nil } }

        return page.lines.reversed().prefix { lines[$0].image != nil }.count
    }

    // MARK: - What the reader asks for

    /// One line as the column set it.
    ///
    /// A justified line that does not end its paragraph is meant to reach the measure exactly, so this
    /// is what a test reads to say whether it did.
    struct TypesetLine {
        var text: String
        var width: CGFloat
        /// How deep the line stands, the space under it included.
        var height: CGFloat
        /// Why the column left this line short, where it did.
        var shortReason: String?
        var startsParagraph: Bool
        var endsParagraph: Bool
        var isJustified: Bool
        var isHeading: Bool
        /// The line is a picture rather than text, and the width is the picture's.
        var isImage: Bool
    }

    /// The lines that fall on one page, in the order they were set.
    func typesetLines(onPage index: Int) -> [TypesetLine] {
        guard pages.indices.contains(index) else { return [] }

        return pages[index].lines.map { described(lines[$0]) }
    }

    /// Every line of the chapter, in the order it was set.
    var typesetLines: [TypesetLine] { lines.map { described($0) } }

    private func described(_ line: ColumnComposer.Line) -> TypesetLine {
        TypesetLine(
            text: (text.string as NSString).substring(with: line.characters),
            width: line.origin + line.width,
            height: line.height,
            shortReason: line.shortReason,
            startsParagraph: line.startsParagraph,
            endsParagraph: line.endsParagraph,
            isJustified: line.isJustified,
            isHeading: line.isHeading,
            isImage: line.image != nil
        )
    }

    /// How many lines of the chapter's own text, its heading aside, fall on a page.
    ///
    /// What decides whether a chapter may share the page the one before it ended on: the free space
    /// says nothing on its own, because a heading is far taller than the lines it is measured in.
    func bodyLineCount(onPage index: Int) -> Int {
        guard pages.indices.contains(index) else { return 0 }

        return lines[pages[index].lines].filter { !$0.isHeading }.count
    }

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
        let string = text.string as NSString
        var result = 0

        for index in 0 ..< min(laidOut, string.length) where string.character(at: index) != Self.softHyphen {
            result += 1
        }

        return result
    }

    private func laidOutOffset(_ source: Int) -> Int {
        let string = text.string as NSString
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
    ///
    /// The text matrix is flipped because a UIKit context counts downwards and CoreText sets glyphs
    /// upwards; without it every line draws on its head.
    func draw(page index: Int) {
        guard pages.indices.contains(index), let drawing = UIGraphicsGetCurrentContext() else { return }

        let page = pages[index]
        var cursor = context.textRect.minY + (index == 0 ? startOffset : 0)

        drawing.saveGState()
        drawing.textMatrix = CGAffineTransform(scaleX: 1, y: -1)

        for line in page.lines {
            if let picture = lines[line].image {
                // The picture is centred in everything the page gave it, its own line's spacing
                // included, so what stands above it matches what stands below.
                let allotted = lines[line].height + page.imagePadding * 2
                let top = cursor + (allotted - lines[line].imageSize.height) / 2

                picture.draw(
                    in: CGRect(
                        origin: CGPoint(x: context.textRect.minX + lines[line].origin, y: top),
                        size: lines[line].imageSize
                    ),
                    palette: context.style.palette,
                    into: drawing
                )
                cursor += allotted + page.leading
                continue
            }

            if let drawn = lines[line].drawn {
                drawing.textPosition = CGPoint(
                    x: context.textRect.minX + lines[line].origin,
                    y: cursor + lines[line].baseline
                )
                CTLineDraw(drawn, drawing)
            }

            cursor += lines[line].height + page.leading
        }

        drawing.restoreGState()
    }

    /// The page's text, for VoiceOver and for the reader's own accessibility label.
    func pageText(_ index: Int) -> String {
        guard pageRanges.indices.contains(index) else { return "" }

        // Without stripping them, VoiceOver reads a page full of soft hyphens. A picture is drawn and
        // so invisible to it, and is named instead: the page says one is there rather than skipping it.
        return (text.string as NSString)
            .substring(with: pageRanges[index])
            .replacingOccurrences(of: String(Typography.softHyphen), with: "")
            .replacingOccurrences(of: "\u{2060}", with: "")
            .replacingOccurrences(of: String(ChapterPagination.pictureMark), with: String(localized: "Picture."))
    }
}
