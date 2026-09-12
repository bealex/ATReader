//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import CryptoKit
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
public final class ChapterLayout {
    /// How the pages of a chapter are laid out, before any text is fetched.
    ///
    /// A page fills the screen, so the text has to keep clear of the notch and the home indicator as
    /// well as of the reader's own margins.
    public struct Context: Equatable, Sendable {
        public var style: ChapterTextStyle
        public var margins: Double
        public var pageSize: CGSize
        public var safeArea: EdgeInsets
        /// False for text that is not a page of the book: a note in a popup has no title above it and
        /// no page number below, so it keeps the band those would have stood in.
        public var hasRunningHeads: Bool

        public init(
            style: ChapterTextStyle,
            margins: Double,
            pageSize: CGSize,
            safeArea: EdgeInsets,
            hasRunningHeads: Bool = true
        ) {
            self.style = style
            self.margins = margins
            self.pageSize = pageSize
            self.safeArea = safeArea
            self.hasRunningHeads = hasRunningHeads
        }

        /// The band kept at the top and bottom of every page for the book title and the page number,
        /// which is as deep as the head drawn in it and no deeper.
        public static let runningHeadHeight: CGFloat = 26

        /// Where the body text is laid out and drawn, in the page's own coordinates.
        public var textRect: CGRect {
            let band = hasRunningHeads ? Self.runningHeadHeight : 0

            return CGRect(origin: .zero, size: pageSize).inset(by: UIEdgeInsets(
                // Half the margin above and below: the running head's own band already parts the text
                // from the edge, where the sides have nothing but the margin to do it.
                top: safeArea.top + margins / 2 + band,
                left: safeArea.leading + margins,
                bottom: safeArea.bottom + margins / 2 + band,
                right: safeArea.trailing + margins
            ))
        }

        public var textSize: CGSize { textRect.size }

        public var isUsable: Bool { textRect.width > 1 && textRect.height > 1 }

        /// Everything about the setting that moves where a line breaks, as one string.
        ///
        /// Measurements a book has already been through are kept against this, so a book reopened at
        /// the same settings costs a read rather than laying every chapter out again. The page's
        /// colours and how its pictures take them are deliberately absent: they change nothing about
        /// where anything sits, and including them would throw the whole book away every time the
        /// reader crossed into the dark.
        public var fingerprint: String {
            [
                ChapterLayout.rulesVersion,
                style.face.rawValue,
                style.weight.rawValue,
                "\(style.fontSize)", "\(style.lineSpacing)", "\(style.letterSpacing)",
                "\(style.justifiesRussian)", "\(style.justifiesEnglish)",
                "\(margins)", "\(pageSize.width)x\(pageSize.height)",
                "\(safeArea.top),\(safeArea.leading),\(safeArea.bottom),\(safeArea.trailing)",
                // Only a page that is not one of the book's own says so, which leaves every book
                // already measured with the fingerprint it was measured under.
                hasRunningHeads ? nil : "noheads",
                style.indentsParagraphs ? nil : "noindent",
            ].compactMap { $0 }.joined(separator: "|")
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
    public nonisolated static let rulesVersion = "17"

    public enum Rules {
        /// Lines that have to follow a heading rather than leaving it stranded at the foot of a page.
        static let linesAfterHeading = 2
        /// However hard the other rules push, a page keeps at least this many lines.
        static let minimumLines = 4
        /// A chapter's last page reads as a mistake with fewer lines than this.
        static let shortLastPage = 3
        /// How far a line gap may be squeezed to pull one more line onto a page.
        public static let tightening: CGFloat = 0.75
        /// How far a line gap may open to take up the slack a rule left behind.
        static let loosening: CGFloat = 3
        /// What one broken rule costs. Far above any amount of uneven depth, so the rules still decide
        /// where a page may break and evenness only chooses between the breaks they allow.
        static let brokenRule: Double = 1000
        /// What each line a chapter's last page falls short of a decent ending costs.
        static let thinLastPage: Double = 40
    }

    /// Text longer than this is worth telling the reader about while it is being laid out.
    public static let progressThreshold = 239 * 1024

    public nonisolated let chapterId: Int
    public let context: Context

    /// What the previous chapter already used on this chapter's first page, when the chapter runs on
    /// from it rather than starting a page of its own.
    public private(set) var startOffset: CGFloat
    /// Where columns already broken into lines are kept, where there is anywhere to keep them.
    private let columns: (any ColumnStore)?

    /// The character range each page covers, so a reading position survives a change of font.
    public private(set) var pageRanges: [NSRange] = []

    let text: NSAttributedString
    private let headingLength: Int

    private(set) var lines: [ColumnComposer.Line] = []
    private(set) var pages: [Page] = []
    /// Each line's CoreText line, built the first time a page draws the line or looks into it.
    private var drawnLines: [Int: CTLine] = [:]
    /// The break search's own table, kept so a chapter cut again at another offset is not searched twice.
    private var breaks: PageCutter.Breaks?

    /// One page: the lines it carries and the space added to (or taken from) each gap between them.
    struct Page: Sendable {
        var lines: Range<Int>
        var leading: CGFloat
        /// Air set above and below each picture on the page, which is what centres one in its space.
        var imagePadding: CGFloat = 0
    }

    init(
        chapterId: Int,
        text: ChapterPagination.TypesetText,
        context: Context,
        startOffset: CGFloat = 0,
        columns: (any ColumnStore)? = nil
    ) {
        self.chapterId = chapterId
        self.context = context
        self.startOffset = max(0, startOffset)
        self.columns = columns
        self.headingLength = text.headingLength
        self.text = text.attributed
    }

    /// Lays a chapter out and cuts it into pages.
    ///
    /// The paragraphs are set away from the main actor, on every core at once; only cutting the column
    /// into pages and drawing them happen here.
    public static func make(
        chapterId: Int,
        content: ChapterContent,
        heading: ChapterHeading,
        context: Context,
        startOffset: CGFloat = 0,
        columns: (any ColumnStore)? = nil,
        onProgress: (@MainActor (Double) -> Void)? = nil
    ) async -> ChapterLayout {
        // The pictures are read off the device before anything is measured: a line as deep as a plate
        // cannot be set without knowing how deep the plate is.
        let images = await BookImages.shared.prepare(sources: content.imageSources)
        // Both settings take every break the dictionary offers: a hyphen evens a ragged edge as surely as
        // it fills a justified line.
        let paragraphs = content.hyphenated
        let language = content.language
        let style = context.style
        let typesetting: @Sendable () -> ChapterPagination.TypesetText = {
            ChapterPagination.typeset(
                paragraphs: paragraphs,
                heading: heading,
                language: language,
                style: style,
                images: images
            )
        }
        let layout = ChapterLayout(
            chapterId: chapterId,
            text: typesetting(),
            context: context,
            startOffset: startOffset,
            columns: columns
        )
        await layout.build(typesetting: { typesetting().attributed }, onProgress: onProgress)
        return layout
    }

    /// True when laying this chapter out takes long enough that the reader should be told.
    public var isLong: Bool { text.string.utf8.count > Self.progressThreshold }

    private func build(
        typesetting: @escaping @Sendable () -> NSAttributedString,
        onProgress: (@MainActor (Double) -> Void)?
    ) async {
        guard context.isUsable, text.length > 0 else { return }

        if let kept = await keptLines() {
            lines = kept
        } else {
            lines = await ColumnComposer.compose(
                paragraphs: ColumnComposer.paragraphs(in: text),
                typesetting: typesetting,
                headingLength: headingLength,
                size: context.textSize,
                onProgress: isLong ? onProgress : nil
            )
            await keep(lines)
        }

        dropTheAirAtTheTop()
        await cutPages()
    }

    /// Cuts the chapter again for a different opening offset.
    ///
    /// Only the first page's depth turns on that offset, so the column stands, the search's table
    /// stands, and all that is worked out again is where the first page ends.
    public func recut(startOffset: CGFloat) async {
        guard startOffset != self.startOffset, !lines.isEmpty else { return }

        self.startOffset = startOffset
        dropTheAirAtTheTop()
        await cutPages()
    }

    private func cutPages() async {
        let cutting = cutter
        let known = breaks
        let offset = startOffset
        let (found, cut) = await cutting.away(from: offset, using: known)

        breaks = found
        pages = cut.pages
        pageRanges = cut.ranges
    }

    /// The lines this chapter was broken into last time, where they were broken for this text at this
    /// setting. Nothing else will do: the whole point of them is that they are what would be composed.
    private func keptLines() async -> [ColumnComposer.Line]? {
        guard
            let columns,
            let kept = await columns.column(chapterId: chapterId, fingerprint: keptUnder)
        else {
            return nil
        }

        let column = await Task.detached(priority: .userInitiated) { () -> ColumnComposer.Column? in
            guard let unpacked = try? (kept as NSData).decompressed(using: .zlib) as Data else { return nil }

            return try? JSONDecoder().decode(ColumnComposer.Column.self, from: unpacked)
        }.value

        guard let column, !column.lines.isEmpty else { return nil }

        return column.lines
    }

    private func keep(_ lines: [ColumnComposer.Line]) async {
        guard let columns, !lines.isEmpty, ColumnComposer.isKeepable(lines) else { return }

        let column = ColumnComposer.Column(lines: lines)
        let squeezed = await Task.detached(priority: .utility) { () -> Data? in
            guard let written = try? JSONEncoder().encode(column) else { return nil }

            return try? (written as NSData).compressed(using: .zlib) as Data
        }.value

        guard let squeezed else { return }

        await columns.store(column: squeezed, chapterId: chapterId, fingerprint: keptUnder)
    }

    /// What a kept column is filed against: the setting it was broken for, and the text it was broken
    /// from. The setting carries the rules version, so a change to how a line is broken throws away
    /// every column kept under the old rules rather than drawing yesterday's lines.
    private lazy var keptUnder: String = {
        var hasher = SHA256()

        hasher.update(data: Data(context.fingerprint.utf8))
        hasher.update(data: Data(text.string.utf8))

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }()

    /// Cuts the air above the chapter's first line back where the chapter starts a page of its own.
    ///
    /// A title keeps its air by standing in it, and at the head of a page there is nothing above it to
    /// stand clear of: the twelve lines a chapter keeps would push its title a third of the way down
    /// its own opening page. Two are left, so the title is not hard against the top edge. A chapter
    /// that runs on from the one before it keeps every bit of its air, which is the point of having it.
    private func dropTheAirAtTheTop() {
        guard startOffset == 0, let first = lines.indices.first, lines[first].titleAir > 0 else { return }

        let kept = min(lines[first].titleAir, TitleBlock.atTheTopOfAPage * context.style.pageLine)
        let dropped = lines[first].titleAir - kept

        lines[first].height -= dropped
        lines[first].baseline -= dropped
        lines[first].titleAir = kept
    }

    // MARK: - Cutting the column into pages

    /// This chapter's column, flattened to what the cutting reads.
    private var cutter: PageCutter {
        PageCutter(
            slugs: lines.map(\.slug),
            depth: context.textSize.height,
            pageLine: context.style.pageLine,
            referenceLineHeight: max(1, context.style.fontSize + context.style.lineSpacing)
        )
    }

    private func height(ofPageAt index: Int) -> CGFloat {
        context.textSize.height - (index == 0 ? startOffset : 0)
    }

    // MARK: - What the reader asks for

    /// One line as the column set it.
    ///
    /// A justified line that does not end its paragraph is meant to reach the measure exactly, so this
    /// is what a test reads to say whether it did.
    public struct TypesetLine {
        public var text: String
        public var width: CGFloat
        /// How deep the line stands, the space under it included.
        public var height: CGFloat
        /// Why the column left this line short, where it did.
        public var shortReason: String?
        /// How far the line's gaps stand open, against the width the font gives a space.
        public var gapMultiple: CGFloat
        /// How many gaps the line had to open, which is all it could fill itself from.
        public var gaps: Int
        public var startsParagraph: Bool
        public var endsParagraph: Bool
        public var isJustified: Bool
        public var isHeading: Bool
        /// The line is a picture rather than text, and the width is the picture's.
        public var isImage: Bool
        /// Where the line's baseline sits below its own top, the air above it included.
        public var baseline: CGFloat
    }

    /// The lines that fall on one page, in the order they were set.
    public func typesetLines(onPage index: Int) -> [TypesetLine] {
        guard pages.indices.contains(index) else { return [] }

        return pages[index].lines.map { described(lines[$0]) }
    }

    /// Every line of the chapter, in the order it was set.
    public var typesetLines: [TypesetLine] { lines.map { described($0) } }

    private func described(_ line: ColumnComposer.Line) -> TypesetLine {
        TypesetLine(
            text: (text.string as NSString).substring(with: line.characters),
            width: line.origin + line.width,
            height: line.height,
            shortReason: line.shortReason,
            gapMultiple: line.gapMultiple,
            gaps: line.gaps,
            startsParagraph: line.startsParagraph,
            endsParagraph: line.endsParagraph,
            isJustified: line.isJustified,
            isHeading: line.isHeading,
            isImage: line.image != nil,
            baseline: line.baseline
        )
    }

    /// How many lines of the chapter's own text, its heading aside, fall on a page.
    ///
    /// What decides whether a chapter may share the page the one before it ended on: the free space
    /// says nothing on its own, because a heading is far taller than the lines it is measured in.
    public func bodyLineCount(onPage index: Int) -> Int {
        guard pages.indices.contains(index) else { return 0 }

        return lines[pages[index].lines].filter { !$0.isHeading }.count
    }

    public var pageCount: Int { pages.count }

    public var isEmpty: Bool { pages.isEmpty }

    /// What is left on the last page, for deciding whether the next chapter can run on from here.
    public var tailFreeSpace: CGFloat {
        guard let page = pages.last else { return 0 }

        let used = page.lines.reduce(CGFloat(0)) { $0 + lines[$1].height }
        return max(0, height(ofPageAt: pages.count - 1) - used)
    }

    /// The page a character offset falls on, so a change of font keeps the reader's place.
    public func pageIndex(containing offset: Int) -> Int {
        let laidOut = laidOutOffset(offset)
        return pageRanges.firstIndex { NSLocationInRange(laidOut, $0) } ?? max(0, min(offset, pageCount - 1))
    }

    /// How far the chapter's own text runs, counted the way a reading position is.
    public var sourceLength: Int { sourceOffset((text.string as NSString).length) }

    public func characterOffset(ofPage index: Int) -> Int {
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

    /// A line's CoreText line, set from the chapter's own text the first time anything asks for it.
    func drawnLine(_ index: Int) -> CTLine? {
        if let held = drawnLines[index] { return held }

        guard
            let setting = lines[index].setting,
            let built = ParagraphRuler.line(in: text, setting: setting)
        else { return nil }

        drawnLines[index] = built
        return built
    }

    /// Draws a page, line by line, so the page's own leading can be applied as it goes.
    ///
    /// The text matrix is flipped because a UIKit context counts downwards and CoreText sets glyphs
    /// upwards; without it every line draws on its head.
    public func draw(page index: Int) {
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

            if let drawn = drawnLine(line) {
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

    /// The note whose marker stands under a point on a page, in the page's own coordinates.
    ///
    /// Walked the same way the page is drawn, so what a finger finds is what the reader can see. The
    /// marker carries the note on its own glyph run, which saves counting characters back through the
    /// soft hyphens the line was set with.
    public func note(at point: CGPoint, onPage index: Int) -> NoteHit? {
        guard pages.indices.contains(index) else { return nil }

        let page = pages[index]
        var cursor = context.textRect.minY + (index == 0 ? startOffset : 0)

        for line in page.lines {
            let allotted = lines[line].height + (lines[line].image != nil ? page.imagePadding * 2 : 0)

            defer { cursor += allotted + page.leading }

            guard point.y >= cursor, point.y < cursor + allotted, let drawn = drawnLine(line) else { continue }

            let origin = context.textRect.minX + lines[line].origin

            guard let found = note(at: point.x - origin, in: drawn) else { return nil }

            return NoteHit(
                id: found.id,
                rect: CGRect(x: origin + found.start, y: cursor, width: found.width, height: lines[line].height)
            )
        }

        return nil
    }

    /// A marker found in a line: which note it points at, and where along the line it stands.
    private struct FoundNote {
        var id: String
        var start: CGFloat
        var width: CGFloat
    }

    /// Every note a page refers to, in the order its markers stand on it.
    ///
    /// Drawn text is invisible to VoiceOver, so a marker cannot be reached by touch there. The reader
    /// offers these as actions on the page instead.
    public func notes(onPage index: Int) -> [String] {
        guard pages.indices.contains(index) else { return [] }

        var result: [String] = []

        for line in pages[index].lines {
            guard let runs = drawnLine(line).flatMap({ CTLineGetGlyphRuns($0) as? [CTRun] }) else { continue }

            for glyphs in runs {
                let attributes = CTRunGetAttributes(glyphs) as NSDictionary

                guard
                    let note = attributes[NSAttributedString.Key.bookNote] as? String,
                    !result.contains(note)
                else { continue }

                result.append(note)
            }
        }

        return result
    }

    /// The note marked in a line at a distance along it, where one stands close enough to be meant.
    private func note(at distance: CGFloat, in line: CTLine) -> FoundNote? {
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return nil }

        for glyphs in runs {
            let attributes = CTRunGetAttributes(glyphs) as NSDictionary

            guard let note = attributes[NSAttributedString.Key.bookNote] as? String else { continue }

            let width = CGFloat(CTRunGetTypographicBounds(glyphs, CFRange(location: 0, length: 0), nil, nil, nil))
            let start = CTLineGetOffsetForStringIndex(line, CTRunGetStringRange(glyphs).location, nil)
            // A superscript digit is a couple of points across, so the target is widened about the
            // marker's middle rather than drawn from its ink.
            let middle = start + width / 2
            let reach = max(width, NoteMarker.target) / 2

            if abs(distance - middle) <= reach { return FoundNote(id: note, start: start, width: width) }
        }

        return nil
    }

    /// The page's text, for VoiceOver and for the reader's own accessibility label.
    public func pageText(_ index: Int) -> String {
        guard pageRanges.indices.contains(index) else { return "" }

        // Without stripping them, VoiceOver reads a page full of soft hyphens. A picture is drawn and
        // so invisible to it, and is named instead: the page says one is there rather than skipping it.
        return (text.string as NSString)
            .substring(with: pageRanges[index])
            .replacingOccurrences(of: String(Typography.softHyphen), with: "")
            .replacingOccurrences(of: "\u{2060}", with: "")
            .replacingOccurrences(
                of: String(ChapterPagination.pictureMark),
                with: String(localized: "Picture.", bundle: .module)
            )
    }
}
