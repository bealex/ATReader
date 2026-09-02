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
        /// the same settings costs a read rather than laying every chapter out again. The text colour
        /// is deliberately absent: it changes nothing about where anything sits, and including it
        /// would throw the whole book away every time the reader crossed into the dark.
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
    /// Bumped whenever a rule below changes where a line breaks or how far one is opened.
    ///
    /// Measurements are kept against the setting they were made at, and the setting alone says nothing
    /// about the rules that read it. Without this, changing how far a mark hangs would leave every book
    /// on the device showing the breaks an older layout chose.
    nonisolated static let rulesVersion = "7"

    enum Rules {
        /// Lines that have to follow a heading rather than leaving it stranded at the foot of a page.
        static let linesAfterHeading = 2
        /// However hard the other rules push, a page keeps at least this many lines.
        static let minimumLines = 4
        /// A chapter's last page reads as a mistake with fewer lines than this.
        static let shortLastPage = 3
        /// How far the letters of a paragraph may close up to save a word from being broken, as a
        /// share of the type size.
        static let letterTightening: CGFloat = 0.02
        /// How far a line gap may be squeezed to pull one more line onto a page.
        static let tightening: CGFloat = 0.75
        /// How far a line gap may open to take up the slack a rule left behind.
        static let loosening: CGFloat = 3
        /// What one broken rule costs. Far above any amount of uneven depth, so the rules still decide
        /// where a page may break and evenness only chooses between the breaks they allow.
        static let brokenRule: Double = 1000
        /// What each line a chapter's last page falls short of a decent ending costs.
        static let thinLastPage: Double = 40
        /// How far TextKit opens a space before it starts taking the rest from between the letters.
        /// Measured across gap counts and measures: it stops at a shade over three times the width the
        /// font gives a space, every time.
        static let textKitSpaceLimit: CGFloat = 3.1
        /// How far a space may be opened here. Twice what TextKit allows itself, so a line reaches for
        /// the gaps between the words long before it reaches for the gaps inside them.
        static let spaceLimit: CGFloat = 6.2
        /// How far back from a break to look for a better one, in characters.
        static let breakSearch = 28
        /// The least a line must keep when a break is moved back off it.
        static let shortestLineTail = 12
        /// What moving a break has to save before it is worth making, so the setting holds still where
        /// the gain would not be seen.
        static let movedBreakGain: Double = 0.35
        /// How many lines before a crowded one may be set again with it.
        static let rebreakWindow = 4
        /// The most break points weighed in one paragraph, so a long one cannot run away with the work.
        static let mostBreakCandidates = 400
        /// Paragraphs longer than this are left as TextKit set them; setting one again costs more than
        /// the crowded line in it is worth.
        static let longestRebreak = 24
        /// What leaving a tied short word at a line's end costs, so it happens only where it earns its
        /// place against the gap it closes.
        static let brokenTie: Double = 6
        /// How far a space may be narrowed to draw one more word onto a line, against its own width.
        ///
        /// Without this there is nothing to choose. Every line can only be set looser than the font
        /// sets it, so filling each one as full as it will go — which is what TextKit already does — is
        /// the cheapest arrangement there is, and no rearranging can beat it. Room to set a line tight
        /// is what lets a word be drawn up from the line below to close a gap.
        static let spaceSqueeze: CGFloat = 0.3
        /// What narrowing a space costs against opening one by as much, since words run together worse
        /// than they drift apart.
        static let squeezePenalty: Double = 3
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
        var layout = ChapterLayout(chapterId: chapterId, text: text, context: context, startOffset: startOffset)
        await layout.build(onProgress: onProgress)

        // Each further pass is asked for rather than run every time: it costs another laying-out of the
        // chapter. See `freedText` and `tightenedText`.
        for rewrite in [ { layout.freedText() }, { layout.tightenedText() } ] {
            guard let rewritten = rewrite() else { continue }

            let again = ChapterLayout(
                chapterId: chapterId,
                text: ChapterPagination.TypesetText(attributed: rewritten, headingLength: text.headingLength),
                context: context,
                startOffset: startOffset
            )
            await again.build(onProgress: nil)
            layout = again
        }

        return layout
    }

    /// True when laying this chapter out takes long enough that the reader should be told.
    var isLong: Bool { storage.string.utf8.count > Self.progressThreshold }

    private func build(onProgress: (@MainActor (Double) -> Void)?) async {
        guard context.isUsable, storage.length > 0 else { return }

        await layoutColumn(onProgress: isLong ? onProgress : nil)
        collectLines()
        rebreakCrowdedLines()
        loosenCrowdedLines()
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

    // MARK: - Lines TextKit would pull apart

    /// A line justified here rather than by TextKit: its own text, and where each run of it sits.
    ///
    /// The storage is held and not just the layout manager. A text storage owns the managers that read
    /// it, never the other way about, so a manager whose storage has gone leaves the line blank.
    private struct LoosenedLine {
        let storage: NSTextStorage
        let manager: NSLayoutManager
        /// One run of glyphs per word, and how far right of its natural place it is drawn.
        let runs: [(glyphs: NSRange, offset: CGFloat)]
    }

    /// One line laid out on its own, the way the font sets it.
    private struct NaturalPiece {
        let storage: NSTextStorage
        let manager: NSLayoutManager
        let container: NSTextContainer
        let width: CGFloat
    }

    private var loosenedLines: [Int: LoosenedLine] = [:]

    /// Justifies the lines whose words TextKit would otherwise have pulled apart.
    ///
    /// Justification opens the spaces first and falls back on the gaps between letters once the spaces
    /// are as wide as it will make them. Measured across gap counts and measures, that ceiling is a
    /// shade over three times the width the font gives a space, and a line asking for more than that
    /// gets its letters set as much as 20% further apart, which reads as words coming to pieces.
    ///
    /// Nothing moves that ceiling: hyphenation, kerning, tracking and ligatures were all measured and
    /// justify identically. So a line that reaches it is set out again here, with the slack going into
    /// the spaces alone until they are twice as wide as TextKit would have allowed. Past that the words
    /// would be too far apart to read as a line, and TextKit's own setting is left to stand.
    private func loosenCrowdedLines() {
        let spaceWidth = " ".size(withAttributes: [ .font: context.style.font ]).width
        let measure = context.textSize.width

        guard spaceWidth > 0 else { return }

        for index in lines.indices {
            // A line whose break was moved is already drawn here, holding its new text.
            guard loosenedLines[index] == nil else { continue }
            // The last line of a paragraph is never justified, so it is already as wide as it wants.
            guard !lines[index].endsParagraph, isJustified(lines[index]) else { continue }

            // A line opening on the dash of speech is set here however TextKit left it. The gap after
            // the dash has to be the one the font gives on every such line, and TextKit opens it along
            // with the others whenever it justifies.
            let hang = hang(lines[index].characters)

            // A line opening on the dash of speech is set here however TextKit left it. The gap after
            // the dash has to be the one the font gives on every such line, and TextKit opens it along
            // with the others whenever it justifies. So is a line with something to hang, since only a
            // line set here can put a character outside the measure.
            if hang == 0, !opensOnDash(lines[index]) {
                // Reading one space off the justified line says whether TextKit ran out of room in them.
                guard
                    let stretched = firstSpaceWidth(lines[index]),
                    stretched >= spaceWidth * Rules.textKitSpaceLimit
                else { continue }
            }

            loosenedLines[index] = loosened(
                range: lines[index].characters,
                startsParagraph: lines[index].startsParagraph,
                measure: measure,
                hang: hang,
                widestGap: spaceWidth * (Rules.spaceLimit - 1)
            )
        }
    }

    /// A line drawn here rather than by TextKit: set as the font sets it, then its words pushed apart
    /// evenly until it fills its measure, so the slack never reaches inside a word.
    private func loosened(
        range: NSRange,
        startsParagraph: Bool,
        measure: CGFloat,
        hang: CGFloat,
        widestGap: CGFloat?
    ) -> LoosenedLine? {
        guard let natural = naturalPiece(for: range, startsParagraph: startsParagraph) else { return nil }
        // A piece is one line and is laid out in a container that holds one, so anything that did not
        // fit was never laid out and must not be drawn as though it had been.
        guard
            natural.manager.glyphRange(for: natural.container).length == natural.manager.numberOfGlyphs
        else { return nil }

        let words = wordRuns(in: natural.storage)

        // The dash that opens a line of speech stands at the left edge of the column as much as the
        // margin does. Opening the gap after it moves the first letter and bends that edge down the
        // page, so the gap keeps the width the font gives it and the rest of the line takes the slack.
        let held = opensOnDash(natural.storage, first: words.first) ? 1 : 0
        let stretchable = words.count - 1 - held

        // Nothing left on the line to open.
        guard stretchable > 0 else { return unfilled(natural) }

        // The measure the words are set to, opened by however far the line's last character hangs
        // outside it. The words carry that extra between them, so the character ends up past the
        // margin and the letters before it stop where the eye expects the edge to be.
        let perGap = (measure + hang - natural.width) / CGFloat(stretchable)
        let spaceWidth = " ".size(withAttributes: [ .font: context.style.font ]).width

        // Negative where the line was set tight to draw a word up from the one below it.
        guard perGap > -spaceWidth * Rules.spaceSqueeze else { return nil }

        // Past this the words would be too far apart to read as one line, so the line is left short.
        // Giving it back to TextKit is the worse answer: having opened the spaces as far as it will,
        // TextKit fills the line from between the letters instead.
        if let widestGap, perGap > widestGap { return unfilled(natural) }

        let runs = words.enumerated().map { position, characters in
            (
                glyphs: natural.manager.glyphRange(forCharacterRange: characters, actualCharacterRange: nil),
                offset: perGap * CGFloat(max(0, position - held))
            )
        }

        return LoosenedLine(storage: natural.storage, manager: natural.manager, runs: runs)
    }

    // MARK: - Paragraphs set again to make room

    /// Sets the last few lines of a paragraph again where the one at the end of them came out crowded.
    ///
    /// TextKit breaks one line at a time and takes all it can each time, so wherever a long word will
    /// not fit, the line before it is left holding too little and has to stand wide open. The text it
    /// wants is above it, in lines that were each filled without regard for what came after.
    ///
    /// So the run of lines ending at the crowded one is set again as a whole. Every arrangement of their
    /// breaks is costed — how far each line has to open its spaces, squared, so one line opened wide
    /// counts for more than several opened a little — and the cheapest is kept. The number of lines
    /// never changes, only where they break, so nothing below moves and the pages stay as composed.
    ///
    /// The window is bounded, so a long paragraph costs no more to set again than a short one.
    private func rebreakCrowdedLines() {
        let spaceWidth = " ".size(withAttributes: [ .font: context.style.font ]).width
        let measure = context.textSize.width

        guard spaceWidth > 0, lines.count > 1 else { return }

        var index = 0

        while index < lines.count {
            guard
                isCrowded(index, spaceWidth: spaceWidth)
            else {
                index += 1
                continue
            }

            let paragraph = paragraph(containing: index)

            if paragraph.count > 1, paragraph.count <= Rules.longestRebreak,
                    rebreak(paragraph, measure: measure, spaceWidth: spaceWidth) {
                index = paragraph.upperBound
            } else {
                index = max(index + 1, paragraph.upperBound)
            }
        }
    }

    /// True where TextKit has opened this line's spaces as far as it will and is taking the rest from
    /// between the letters, or where the line has no space on it to open at all.
    private func isCrowded(_ index: Int, spaceWidth: CGFloat) -> Bool {
        guard !lines[index].endsParagraph, isJustified(lines[index]) else { return false }
        guard let opened = firstSpaceWidth(lines[index]) else { return true }

        return opened >= spaceWidth * Rules.textKitSpaceLimit
    }

    /// The whole paragraph a line belongs to.
    ///
    /// The run has to reach the paragraph's end, not stop at the crowded line. Fixing both ends of a run
    /// and its number of lines leaves the arrangement TextKit already found as the only one that fits:
    /// it fills every line to the brim, so shortening any of them pushes a later one past the measure.
    /// A paragraph's last line is ragged and takes whatever is left, and that slack is the room every
    /// other line in it needs to move.
    private func paragraph(containing index: Int) -> Range<Int> {
        var first = index

        while first > 0, !lines[first - 1].endsParagraph { first -= 1 }

        var last = index

        while last + 1 < lines.count, !lines[last].endsParagraph { last += 1 }

        return first ..< (last + 1)
    }

    /// Everything the costing of one paragraph's breaks needs.
    private struct Setting {
        let start: Int
        let indent: CGFloat
        let measure: CGFloat
        let spaceWidth: CGFloat
        let hyphen: CGFloat
        let offsets: [CGFloat]
    }

    /// Costs every way of breaking a run of lines and keeps the cheapest. Reports whether it changed.
    private func rebreak(_ window: Range<Int>, measure: CGFloat, spaceWidth: CGFloat) -> Bool {
        let first = lines[window.lowerBound]
        let last = lines[window.upperBound - 1]
        let start = first.characters.location
        let ending = last.characters.location + last.characters.length

        guard
            let offsets = offsets(from: start, to: ending, width: measure * CGFloat(window.count + 1))
        else { return false }

        let setting = Setting(
            start: start,
            indent: first.startsParagraph ? headIndent(at: start) : 0,
            measure: measure,
            spaceWidth: spaceWidth,
            hyphen: "-".size(withAttributes: [ .font: context.style.font ]).width,
            offsets: offsets
        )
        let breaks = breakCandidates(from: start, to: ending)

        guard !breaks.isEmpty else { return false }

        var stops = [ start ]
        stops.append(contentsOf: breaks.map(\.position))
        stops.append(ending)

        var current: Double = 0

        for line in window {
            let range = lines[line].characters
            current += cost(
                setting,
                from: range.location,
                until: range.location + range.length,
                isFirst: line == window.lowerBound,
                isLast: line == window.upperBound - 1
            )
        }

        guard
            let cheapest = cheapestBreaks(
                stops: stops,
                ties: breaks.map(\.tied),
                wanted: window.count,
                setting: setting
            ),
            cheapest.total + Rules.movedBreakGain < current
        else { return false }

        return adopt(cheapest.stops, for: window, measure: measure)
    }

    /// What one line costs: how far its spaces have to open to fill the measure, or close to hold one
    /// more word, squared either way so a single line set badly counts for more than several set a
    /// little off.
    private func cost(_ setting: Setting, from: Int, until: Int, isFirst: Bool, isLast: Bool) -> Double {
        let measured = measured(from: from, until: until, setting: setting)
        let available = setting.measure - (isFirst ? setting.indent : 0)
        let slack = available - measured.width

        // Set tight, to draw one more word up. Only so far, and dearer than the same drift apart.
        if slack < 0 {
            let squeeze = -slack / CGFloat(max(1, measured.gaps))

            guard measured.gaps > 0, squeeze <= setting.spaceWidth * Rules.spaceSqueeze else { return .infinity }

            let ratio = Double(squeeze / setting.spaceWidth)
            return ratio * ratio * Rules.squeezePenalty
        }

        // A paragraph's last line stops where the paragraph stops and is never justified, so whatever
        // is left over on it costs nothing. That is the slack the rest of them share.
        guard !isLast, slack > 0 else { return 0 }
        // Nothing to open but the gaps inside the words, which is the worst a line can read.
        guard measured.gaps > 0 else { return Double(slack / setting.spaceWidth) * 20 }

        let growth = Double(slack / CGFloat(measured.gaps) / setting.spaceWidth)
        return growth * growth
    }

    /// The cheapest run of breaks that covers the text in exactly `wanted` lines.
    private func cheapestBreaks(
        stops: [Int],
        ties: [Bool],
        wanted: Int,
        setting: Setting
    ) -> (stops: [Int], total: Double)? {
        var best = [[Double]](repeating: [Double](repeating: .infinity, count: stops.count), count: wanted + 1)
        var came = [[Int]](repeating: [Int](repeating: 0, count: stops.count), count: wanted + 1)
        best[0][0] = 0

        for used in 1 ... wanted {
            for stop in 1 ..< stops.count {
                // A tie broken here leaves a short word at a line's end, which is worth something.
                let tied = stop <= ties.count && ties[stop - 1] && stop < stops.count - 1
                let tiePenalty = tied ? Rules.brokenTie : 0

                for previous in stride(from: stop - 1, through: 0, by: -1) {
                    // Reaching further back only makes the line longer, so once it will not fit at
                    // all, nothing before it will either.
                    let reach =
                        setting.offsets[stops[stop] - setting.start]
                        - setting.offsets[stops[previous] - setting.start]

                    if reach > setting.measure + setting.spaceWidth * 2 { break }

                    guard best[used - 1][previous] < .infinity else { continue }

                    let line = cost(
                        setting,
                        from: stops[previous],
                        until: stops[stop],
                        isFirst: previous == 0,
                        isLast: used == wanted
                    )

                    guard line < .infinity else { continue }

                    let total = best[used - 1][previous] + line + tiePenalty

                    if total < best[used][stop] {
                        best[used][stop] = total
                        came[used][stop] = previous
                    }
                }
            }
        }

        let total = best[wanted][stops.count - 1]

        guard total < .infinity else { return nil }

        var chosen: [Int] = []
        var stop = stops.count - 1

        for used in stride(from: wanted, through: 1, by: -1) {
            chosen.append(stops[stop])
            stop = came[used][stop]
        }

        chosen.append(setting.start)
        chosen.reverse()
        return (chosen, total)
    }

    /// Puts a chosen run of breaks in place, and draws every line it touches.
    ///
    /// All of them or none: one line redrawn beside one left as TextKit set it would show the words that
    /// moved twice over, or lose them.
    private func adopt(_ stops: [Int], for window: Range<Int>, measure: CGFloat) -> Bool {
        guard stops.count == window.count + 1 else { return false }

        var drawn: [LoosenedLine] = []

        for step in 0 ..< window.count {
            let range = NSRange(location: stops[step], length: stops[step + 1] - stops[step])
            let opensParagraph = step == 0 && lines[window.lowerBound].startsParagraph
            // The paragraph's last line stops where the paragraph stops: it keeps its ragged edge and
            // is drawn as the font sets it.
            let line =
                step == window.count - 1
                ? natural(range: range, startsParagraph: opensParagraph)
                : loosened(
                    range: range,
                    startsParagraph: opensParagraph,
                    measure: measure,
                    hang: hang(range),
                    widestGap: nil
                )

            guard let line else { return false }

            drawn.append(line)
        }

        for step in 0 ..< window.count {
            let index = window.lowerBound + step
            lines[index].characters = NSRange(location: stops[step], length: stops[step + 1] - stops[step])
            lines[index].endsWithHyphen = endsOnSoftHyphen(lines[index])
            loosenedLines[index] = drawn[step]
        }

        return true
    }

    /// A line drawn as the font sets it, with nothing added to fill the measure.
    private func natural(range: NSRange, startsParagraph: Bool) -> LoosenedLine? {
        guard let piece = naturalPiece(for: range, startsParagraph: startsParagraph) else { return nil }
        guard piece.manager.glyphRange(for: piece.container).length == piece.manager.numberOfGlyphs else { return nil }

        return unfilled(piece)
    }

    /// The piece as it stands, drawn in one run, so a line that cannot be filled is left short rather
    /// than handed back to TextKit to fill from between the letters.
    private func unfilled(_ piece: NaturalPiece) -> LoosenedLine {
        LoosenedLine(
            storage: piece.storage,
            manager: piece.manager,
            runs: [ (glyphs: NSRange(location: 0, length: piece.manager.numberOfGlyphs), offset: 0) ]
        )
    }

    /// Every place a line may break within a stretch of text, and whether a tie is holding it shut.
    private func breakCandidates(from start: Int, to ending: Int) -> [(position: Int, tied: Bool)] {
        let string = storage.string as NSString
        var result: [(position: Int, tied: Bool)] = []
        var index = start + 1

        while index < ending, result.count < Rules.mostBreakCandidates {
            let before = string.character(at: index - 1)

            if before == 0x20 {
                let tied = index < string.length && string.character(at: index) == Self.wordJoiner
                result.append((index, tied))
            } else if before == Self.softHyphen {
                result.append((index, false))
            }

            index += 1
        }

        return result
    }

    /// How wide a piece of the measured line is, and how many spaces it has to open.
    private func measured(from: Int, until: Int, setting: Setting) -> (width: CGFloat, gaps: Int) {
        let string = storage.string as NSString
        var last = until

        // The space or newline a line breaks at is carried by it but never drawn.
        while last > from, Self.isBlank(string.character(at: last - 1)) { last -= 1 }

        var width = setting.offsets[last - setting.start] - setting.offsets[from - setting.start]

        // A line breaking inside a word is drawn with the hyphen the soft one stands for.
        if last > from, string.character(at: last - 1) == Self.softHyphen { width += setting.hyphen }

        var gaps = 0

        for index in from ..< last where string.character(at: index) == 0x20 { gaps += 1 }

        return (width, gaps)
    }

    /// Where every character of a stretch of text sits when it is set as one unbroken line, so the width
    /// of any piece of it is a subtraction rather than another laying-out.
    private func offsets(from start: Int, to ending: Int, width: CGFloat) -> [CGFloat]? {
        guard start >= 0, ending > start, ending <= storage.length else { return nil }

        let piece = NSMutableAttributedString(
            attributedString: storage.attributedSubstring(from: NSRange(location: start, length: ending - start))
        )

        piece.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: piece.length)) { value, range, _ in
            guard let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle else { return }

            style.alignment = .natural
            style.firstLineHeadIndent = 0
            style.headIndent = 0
            piece.addAttribute(.paragraphStyle, value: style, range: range)
        }

        let pieceStorage = NSTextStorage(attributedString: piece)
        let pieceManager = NSLayoutManager()
        let pieceContainer = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        pieceContainer.lineFragmentPadding = 0
        pieceContainer.maximumNumberOfLines = 1
        pieceManager.usesFontLeading = true
        pieceStorage.addLayoutManager(pieceManager)
        pieceManager.addTextContainer(pieceContainer)
        pieceManager.ensureLayout(for: pieceContainer)

        guard pieceManager.numberOfGlyphs > 0 else { return nil }
        // Every glyph has to have been laid out. One that was not has no position, and a width taken
        // from it would be nonsense that the costing would then trust.
        guard pieceManager.glyphRange(for: pieceContainer).length == pieceManager.numberOfGlyphs else { return nil }

        var result = [CGFloat](repeating: 0, count: piece.length + 1)

        for offset in 0 ..< piece.length {
            result[offset] = pieceManager.location(forGlyphAt: pieceManager.glyphIndexForCharacter(at: offset)).x
        }

        result[piece.length] = pieceManager.usedRect(for: pieceContainer).maxX
        return result
    }

    private func headIndent(at position: Int) -> CGFloat {
        let style = storage.attribute(.paragraphStyle, at: position, effectiveRange: nil)
        return (style as? NSParagraphStyle)?.firstLineHeadIndent ?? 0
    }

    /// True where the line opens a paragraph of speech: a dash, and then a space.
    private func opensOnDash(_ line: Line) -> Bool {
        guard line.startsParagraph else { return false }

        let string = storage.string as NSString
        let start = line.characters.location

        guard start + 1 < string.length, Self.isDash(string.character(at: start)) else { return false }

        return string.character(at: start + 1) == 0x20
    }

    /// True where the piece's first word is the dash that marks speech.
    private func opensOnDash(_ pieceStorage: NSTextStorage, first word: NSRange?) -> Bool {
        guard let word, word.length > 0, word.length <= 2 else { return false }

        let string = pieceStorage.string as NSString

        for index in word.location ..< (word.location + word.length)
        where !Self.isDash(string.character(at: index)) {
            return false
        }

        return true
    }

    private static func isDash(_ character: unichar) -> Bool {
        character == 0x2014 || character == 0x2013 || character == 0x2015 || character == 0x002D
    }

    private func isJustified(_ line: Line) -> Bool {
        let style = storage.attribute(.paragraphStyle, at: line.characters.location, effectiveRange: nil)
        return (style as? NSParagraphStyle)?.alignment == .justified
    }

    /// How far the last character of a line is set outside the measure.
    ///
    /// A justified column is a straight edge of letters, and a line ending in a hyphen or a comma stops
    /// short of it: those marks are mostly the white space around them, so the eye reads the edge as
    /// notched wherever one lands. Setting the mark outside the measure puts the letters back on the
    /// line the rest of the column keeps.
    ///
    /// A fraction rather than the whole character, which is what a straight edge actually wants: hang a
    /// comma entirely and the column bulges where the commas are.
    private func hang(_ range: NSRange) -> CGFloat {
        guard let character = hangingCharacter(in: range), let fraction = Self.hangs[character] else { return 0 }

        return String(character).size(withAttributes: [ .font: context.style.font ]).width * fraction
    }

    /// The character a line ends on, less the space or newline it broke at.
    ///
    /// A line broken inside a word ends on a soft hyphen, which is invisible and has no width; the
    /// hyphen TextKit draws in its place is what hangs, so that is what is measured.
    private func hangingCharacter(in range: NSRange) -> Character? {
        let string = storage.string as NSString
        var index = min(string.length, range.location + range.length) - 1

        while index > range.location, Self.isBlank(string.character(at: index)) { index -= 1 }

        guard index >= range.location, index < string.length else { return nil }

        let character = string.character(at: index)

        guard character != Self.softHyphen else { return "-" }
        guard let scalar = Unicode.Scalar(character) else { return nil }

        return Character(scalar)
    }

    /// How much of a character may sit outside the measure, against its own width.
    ///
    /// A hyphen is a bar through the middle of a wide blank, so most of it hangs. A full stop and a
    /// comma sit low and small and hang nearly as far. A question mark is tall and dark enough to read
    /// as part of the edge, so it barely moves.
    private static let hangs: [Character: CGFloat] = [
        "-": 0.6, "\u{2010}": 0.6, "–": 0.45, "—": 0.3,
        ".": 0.55, ",": 0.55, "…": 0.3, ":": 0.35, ";": 0.4,
        "!": 0.25, "?": 0.2,
        "»": 0.3, "”": 0.35, "’": 0.45, "\"": 0.35, "'": 0.45, ")": 0.15, "]": 0.15,
    ]

    /// True where the line breaks a word, so TextKit is drawing a hyphen at the end of it.
    private func endsOnSoftHyphen(_ line: Line) -> Bool {
        let string = storage.string as NSString
        var index = min(string.length, line.characters.location + line.characters.length) - 1

        while index > line.characters.location, Self.isBlank(string.character(at: index)) {
            index -= 1
        }

        return index >= 0 && index < string.length && string.character(at: index) == Self.softHyphen
    }

    private static func isBlank(_ character: unichar) -> Bool { character == 0x20 || character == 0x0A }

    /// How wide the first space on the line came out once TextKit had justified it.
    private func firstSpaceWidth(_ line: Line) -> CGFloat? {
        let string = storage.string as NSString
        let ending = min(string.length, line.characters.location + line.characters.length)

        for character in line.characters.location ..< ending where string.character(at: character) == 0x20 {
            let glyph = manager.glyphIndexForCharacter(at: character)

            guard glyph + 1 < manager.numberOfGlyphs else { return nil }

            return manager.location(forGlyphAt: glyph + 1).x - manager.location(forGlyphAt: glyph).x
        }

        return nil
    }

    /// The runs of text between the spaces: the words the slack is shared out between.
    private func wordRuns(in pieceStorage: NSTextStorage) -> [NSRange] {
        let string = pieceStorage.string as NSString
        var result: [NSRange] = []
        var start = 0

        for index in 0 ..< string.length where string.character(at: index) == 0x20 {
            result.append(NSRange(location: start, length: index - start))
            start = index + 1
        }

        result.append(NSRange(location: start, length: string.length - start))
        return result.filter { $0.length > 0 }
    }

    /// The line set on its own, the way the font sets it, with the layout kept so it can be drawn.
    private func naturalLine(at index: Int) -> NaturalPiece? {
        naturalPiece(for: lines[index].characters, startsParagraph: lines[index].startsParagraph)
    }

    private func naturalPiece(for range: NSRange, startsParagraph: Bool) -> NaturalPiece? {
        guard range.length > 0, range.location >= 0, range.location + range.length <= storage.length else { return nil }

        let piece = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))

        // A line carries the space or newline it broke at; neither is part of what is drawn.
        while piece.length > 0, let last = piece.string.unicodeScalars.last, last == " " || last == "\n" {
            piece.deleteCharacters(in: NSRange(location: piece.length - 1, length: 1))
        }

        guard piece.length > 0 else { return nil }

        // A soft hyphen is invisible except where a line breaks on it, and a line set on its own breaks
        // nowhere. Putting in the hyphen TextKit would have drawn keeps both its look and its width.
        if piece.string.unicodeScalars.last == Unicode.Scalar(Self.softHyphen) {
            piece.replaceCharacters(in: NSRange(location: piece.length - 1, length: 1), with: "-")
        }

        piece.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: piece.length)) { value, range, _ in
            guard let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle else { return }

            style.alignment = .natural
            // The indent belongs to a paragraph's first line, and this piece is only sometimes that.
            if !startsParagraph { style.firstLineHeadIndent = 0 }

            piece.addAttribute(.paragraphStyle, value: style, range: range)
        }

        let pieceStorage = NSTextStorage(attributedString: piece)
        let pieceManager = NSLayoutManager()
        let pieceContainer = NSTextContainer(size: CGSize(
            width: max(1, context.textSize.width),
            height: .greatestFiniteMagnitude
        ))
        pieceContainer.lineFragmentPadding = 0
        pieceContainer.maximumNumberOfLines = 1
        pieceManager.usesFontLeading = true
        pieceStorage.addLayoutManager(pieceManager)
        pieceManager.addTextContainer(pieceContainer)
        pieceManager.ensureLayout(for: pieceContainer)

        return NaturalPiece(
            storage: pieceStorage,
            manager: pieceManager,
            container: pieceContainer,
            // The right edge, not the width: a paragraph's first line is indented, and the indent
            // sits in the used rect's origin rather than its width. Measuring the width alone left
            // that line believing it had a whole indent more room, and it overran the margin by it.
            width: pieceManager.usedRect(for: pieceContainer).maxX
        )
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

    /// One line as the column set it.
    ///
    /// A justified line that does not end its paragraph is meant to reach the measure exactly, so this
    /// is what a test reads to say whether it did.
    struct TypesetLine {
        var text: String
        var width: CGFloat
        var startsParagraph: Bool
        var endsParagraph: Bool
        var isJustified: Bool
        var isHeading: Bool
    }

    /// Where a line's ink ends, measured from the left edge of the text.
    ///
    /// Not the fragment's used rect: a line the column set itself is drawn run by run, and a line
    /// TextKit justified has moved its glyphs since. Both are missed by asking the fragment.
    private func drawnWidth(_ line: Line) -> CGFloat {
        if let index = lines.firstIndex(where: { $0.characters == line.characters }),
                let loosened = loosenedLines[index],
                let last = loosened.runs.last,
                let box = loosened.manager.textContainers.first {
            return last.offset + loosened.manager.boundingRect(forGlyphRange: last.glyphs, in: box).maxX
        }

        let string = storage.string as NSString
        var characters = line.characters

        while characters.length > 0 {
            let tail = string.substring(with: NSRange(location: NSMaxRange(characters) - 1, length: 1))

            guard tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { break }

            characters.length -= 1
        }

        guard characters.length > 0 else { return 0 }

        let glyphs = manager.glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
        return manager.boundingRect(forGlyphRange: glyphs, in: container).maxX
    }

    /// The lines that fall on one page, in the order they were set.
    func typesetLines(onPage index: Int) -> [TypesetLine] {
        guard pages.indices.contains(index) else { return [] }

        return lines[pages[index].lines].map(described)
    }

    /// Every line of the chapter, in the order it was set.
    var typesetLines: [TypesetLine] { lines.map(described) }

    private func described(_ line: Line) -> TypesetLine {
        return TypesetLine(
            text: (storage.string as NSString).substring(with: line.characters),
            width: drawnWidth(line),
            startsParagraph: line.startsParagraph,
            endsParagraph: line.endsParagraph,
            isJustified: isJustified(line),
            isHeading: line.isHeading
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
    /// Ties a short word to the one after it, so no line may end on it.
    private static let wordJoiner = unichar(0x2060)
    /// The same width as the joiner — none — but a break is allowed here.
    private static let zeroWidthSpace = unichar(0x200B)
    /// The longest word worth leaving at the end of a line to close a gap. Russian ties one- and
    /// two-letter prepositions to what follows them, and those are the ones this frees.
    private static let longestFreedWord = 2

    /// The chapter's text again, with the ties freed on the short words that were holding a line open.
    ///
    /// A one- or two-letter preposition is tied to the word after it so that no line ends on it, and
    /// that tie is a word joiner sitting just after the space. Where the pair would only travel together
    /// by leaving the line before it stretched wide open, the gap reads worse than the broken rule
    /// would, so the tie is given up and the little word stays where it was.
    ///
    /// Only where the line after it carries on the paragraph. Pulling a word back onto a full line at
    /// the expense of a last line that is already short trades one thin line for another.
    ///
    /// The joiner is swapped rather than removed. Both are one character, so every reading position in
    /// the chapter still counts to the same place; deleting it would shift them all.
    /// The chapter set again with a two-line paragraph closed up onto one line.
    ///
    /// A paragraph a fraction wider than the measure costs the eye more as a broken word and a stub
    /// line than as letters standing a little closer.
    func tightenedText() -> NSAttributedString? {
        guard lines.count > 1 else { return nil }

        let measure = context.textSize.width
        let limit = context.style.fontSize * Rules.letterTightening
        let string = storage.string as NSString
        var closed: [(range: NSRange, kern: CGFloat)] = []

        for (index, line) in lines.enumerated() {
            guard !line.isHeading, line.startsParagraph else { continue }
            guard index + 1 < lines.count, lines[index + 1].endsParagraph else { continue }

            let range = NSRange(
                location: line.characters.location,
                length: NSMaxRange(lines[index + 1].characters) - line.characters.location
            )

            guard range.length > 1, NSMaxRange(range) <= string.length else { continue }

            let text = string.substring(with: range)
                .replacingOccurrences(of: "\u{00AD}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard text.count > 1 else { continue }

            let width = (text as NSString).size(withAttributes: [
                .font: context.style.font,
                .kern: context.style.letterSpacing,
            ]).width
            // The opening line is indented, so it holds less than the measure.
            let excess = width - (measure - headIndent(at: line.characters.location))

            guard excess > 0 else { continue }

            let perGap = excess / CGFloat(text.count - 1)

            guard perGap <= limit else { continue }

            closed.append((range, context.style.letterSpacing - perGap))
        }

        guard !closed.isEmpty else { return nil }

        let result = NSMutableAttributedString(attributedString: storage)

        for entry in closed { result.addAttribute(.kern, value: entry.kern, range: entry.range) }

        return result
    }

    func freedText() -> NSAttributedString? {
        let string = storage.string as NSString
        let spaceWidth = " ".size(withAttributes: [ .font: context.style.font ]).width

        guard spaceWidth > 0, lines.count > 1 else { return nil }

        var joiners: [Int] = []

        for index in 0 ..< (lines.count - 1) {
            let line = lines[index]

            // A line that ends its paragraph was never justified in the first place.
            guard !line.endsParagraph, !lines[index + 1].endsParagraph, isJustified(line) else { continue }

            // Opened as far as TextKit will open a space, so the rest is coming out of the letters —
            // or there is no space on the line to open at all. A line the column gave up on filling
            // counts too: what holds it short is the tie below it, which is what this frees.
            let opened = firstSpaceWidth(line)
            let shortfall = context.textSize.width - drawnWidth(line)

            guard
                shortfall > spaceWidth || opened == nil || opened! >= spaceWidth * Rules.textKitSpaceLimit
            else { continue }

            let following = lines[index + 1].characters.location

            guard let found = joiner(afterShortWordAt: following, in: string) else { continue }

            joiners.append(found)
        }

        guard !joiners.isEmpty else { return nil }

        let freed = NSMutableAttributedString(attributedString: storage)
        let replacement = String(UnicodeScalar(Self.zeroWidthSpace) ?? " ")

        for joiner in joiners {
            freed.replaceCharacters(in: NSRange(location: joiner, length: 1), with: replacement)
        }

        return freed
    }

    /// Where the tie is that holds a short word at `start` to the word after it.
    private func joiner(afterShortWordAt start: Int, in string: NSString) -> Int? {
        var index = start

        while index < string.length, string.character(at: index) != 0x20 {
            index += 1
        }

        let length = index - start

        guard length >= 1, length <= Self.longestFreedWord else { return nil }
        guard index + 1 < string.length, string.character(at: index + 1) == Self.wordJoiner else { return nil }

        return index + 1
    }

    /// Draws a page, line by line, so the page's own leading can be applied as it goes.
    func draw(page index: Int) {
        guard pages.indices.contains(index) else { return }

        let page = pages[index]
        var cursor = context.textRect.minY + (index == 0 ? startOffset : 0)

        for line in page.lines {
            // A line justified here is drawn a word at a time, each shifted right of where the font
            // would have put it, so the slack sits between the words and never inside them. Anything
            // that leaves that layout empty falls back to TextKit's: a line whose words are a little
            // far apart is a blemish, a line that isn't drawn is text the reader loses.
            let loosened = loosenedLines[line]

            if let loosened, loosened.manager.numberOfGlyphs > 0 {
                for word in loosened.runs {
                    loosened.manager.drawGlyphs(
                        forGlyphRange: word.glyphs,
                        at: CGPoint(x: context.textRect.minX + word.offset, y: cursor)
                    )
                }
            } else {
                let origin = CGPoint(x: context.textRect.minX, y: cursor - lines[line].columnTop)
                manager.drawGlyphs(forGlyphRange: lines[line].glyphs, at: origin)
            }

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
