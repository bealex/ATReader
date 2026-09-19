//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import CoreText
import SwiftUI
import UIKit

/// One chapter, set as text for one style and one page size, and cut into pages wherever it is read.
///
/// Only the paragraphs around the pages asked for are composed. `ColumnComposer` breaks a paragraph
/// into lines, choosing every break in it together with how each line is filled, and `PageCutter` cuts
/// the lines into a page by the rules a compositor keeps: no line of a paragraph left alone at either
/// end of a page, no hyphen at the foot of one, no heading stranded without its text. Lines are
/// numbered from the first paragraph composed, so a number keeps naming the same line as the composed
/// stretch grows at either end.
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
        /// no progress below, so it keeps the band those would have stood in.
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

        /// How much smaller than the text its running head is set.
        ///
        /// Against the book's own text rather than against the system's type size. The band below is
        /// measured from the same number, and a head that followed a setting the band couldn't see
        /// would grow into the text.
        public static let runningHeadScale: CGFloat = 0.93

        /// How deep the head is drawn, which is what the band is built from.
        public var runningHeadLine: CGFloat {
            UIFont.systemFont(ofSize: style.fontSize * Self.runningHeadScale).lineHeight
        }

        /// The band kept at the top and bottom of every page for the book title and how far into the
        /// book the page is: as deep as the head set in it, and a third as much again of air between
        /// it and the text.
        public var runningHeadBand: CGFloat {
            hasRunningHeads ? max(Self.leastRunningHeadBand, runningHeadLine * Self.runningHeadBandLines) : 0
        }

        /// However shallow the head, the band holds the controls that stand on its line.
        ///
        /// They are a fingertip deep. A screen that keeps a band of its own at that edge lends them the
        /// room, and an iPad keeps none at the top, so without a floor here the controls come down on
        /// the first line of the page and the page moves under them.
        public static let leastRunningHeadBand: CGFloat = 50

        private static let runningHeadBandLines: CGFloat = 1.35

        /// Where the body text is laid out and drawn, in the page's own coordinates.
        public var textRect: CGRect {
            let band = runningHeadBand

            return CGRect(origin: .zero, size: pageSize).inset(by: UIEdgeInsets(
                // The band alone above and below. It holds the head in its middle, so it already parts
                // the text from the edge by as much as stands over the head; adding the margin to that
                // parts it twice. The sides have nothing but the margin to do it.
                top: safeArea.top + band,
                left: safeArea.leading + margins,
                bottom: safeArea.bottom + band,
                right: safeArea.trailing + margins
            ))
        }

        public var textSize: CGSize { textRect.size }

        public var isUsable: Bool { textRect.width > 1 && textRect.height > 1 }
    }

    /// What a compositor would not allow: line counts, the points a line gap may give or take, and what
    /// breaking a rule costs against letting a page come out the wrong depth.
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
        /// How much of its own depth a plate may give up to finish the page it stands on.
        ///
        /// A plate is sized against the whole page, so one standing at two thirds of it can follow no
        /// text at all: it lands on a page of its own and leaves the page before it half empty. Letting
        /// it give a little back is what closes that gap. Below this it is small enough to read as a
        /// different picture, so it takes the page of its own instead.
        static let plateGivesUp: CGFloat = 0.3
        /// How far a picture stands off the text above and below it, against the gap between two lines.
        static let pictureAir: CGFloat = 1.62
    }

    /// One page's worth of a chapter: the lines it carries, and where and how they stand.
    public struct Page: Sendable, Equatable {
        /// A plate at the foot of a page that gave up depth to finish it rather than taking a page of
        /// its own and leaving this one half empty.
        struct Plate: Sendable, Equatable {
            var line: Int
            var height: CGFloat
        }

        public internal(set) var lines: Range<Int>
        /// How far below the top of the text the first line stands: under a chapter that ended higher
        /// up the page, or over an opening set at the foot of it.
        public internal(set) var top: CGFloat = 0
        var leading: CGFloat = 0
        /// Air set above and below each picture on the page, which is what centres one in its space.
        var imagePadding: CGFloat = 0
        var plate: Plate?
        /// The page opens on the chapter's title, which leaves most of its air above the top edge.
        var trimsTitle = false
    }

    public nonisolated let chapterId: Int
    public let context: Context

    let text: NSAttributedString
    private let headingLength: Int
    /// Where each paragraph stands in the text, its closing newline included.
    private let paragraphs: [NSRange]
    /// Where every soft hyphen stands in the text, which is all that parts a place in it from a
    /// reading position.
    private let softHyphens: [Int]
    private let typesetting: @Sendable () -> NSAttributedString
    private let setter: ColumnComposer.Setter

    /// The lines composed so far, in order, the first of them numbered `runStart`.
    private var run: [ColumnComposer.Line] = []
    private var runStart = 0
    /// Which paragraphs those lines are, and the number of each one's first line.
    private var composed = 0 ..< 0
    private var paragraphStarts: [Int] = []
    /// The composing under way, which the next one waits for so the run grows one piece at a time.
    private var composing: Task<Void, Never>?
    /// Each line's CoreText line, built the first time a page draws the line or looks into it.
    private var drawnLines: [Int: CTLine] = [:]
    /// How much of the air over the chapter's title goes where the title opens a page.
    private var titleTrim: CGFloat = 0

    /// Every page of a chapter laid out whole, which only ``make(chapterId:content:heading:context:startOffset:)``
    /// fills. The reader cuts its pages one at a time instead.
    public private(set) var pages: [Page] = []

    private init(
        chapterId: Int,
        text: ChapterPagination.TypesetText,
        context: Context,
        typesetting: @escaping @Sendable () -> NSAttributedString
    ) {
        self.chapterId = chapterId
        self.context = context
        self.text = text.attributed
        self.headingLength = text.headingLength
        self.paragraphs = ColumnComposer.paragraphs(in: text.attributed)
        self.softHyphens = Self.softHyphens(in: text.attributed.string as NSString)
        self.typesetting = typesetting
        self.setter = ColumnComposer.Setter(
            typesetting: typesetting,
            headingLength: text.headingLength,
            size: context.textSize
        )
    }

    /// A chapter ready to be cut into pages anywhere: set as text, its pictures read, and none of it
    /// composed yet.
    public static func prepare(
        chapterId: Int,
        content: ChapterContent,
        heading: ChapterHeading,
        context: Context
    ) async -> ChapterLayout {
        // The pictures are read off the device before anything is measured: a line as deep as a plate
        // cannot be set without knowing how deep the plate is.
        let images = await BookImages.shared.prepare(sources: content.imageSources)
        // Both alignments take every break the dictionary offers, where the reader lets them: a hyphen
        // evens a ragged edge as surely as it fills a justified line.
        let paragraphs = context.style.hyphenates ? content.hyphenated : content.paragraphs
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

        return ChapterLayout(
            chapterId: chapterId,
            text: typesetting(),
            context: context,
            typesetting: { typesetting().attributed }
        )
    }

    /// A chapter composed whole and cut from its first line, for text that is shown all at once.
    ///
    /// - Parameter startOffset: how far down its first page the chapter begins.
    public static func make(
        chapterId: Int,
        content: ChapterContent,
        heading: ChapterHeading,
        context: Context,
        startOffset: CGFloat = 0
    ) async -> ChapterLayout {
        let layout = await prepare(chapterId: chapterId, content: content, heading: heading, context: context)

        guard context.isUsable, !layout.isEmpty else { return layout }

        layout.append(await ColumnComposer.compose(
            paragraphs: layout.paragraphs,
            typesetting: layout.typesetting,
            headingLength: layout.headingLength,
            size: context.textSize
        ))
        layout.pages = layout.cutWhole(top: max(0, startOffset))
        return layout
    }

    /// True where the chapter has no text at all to set.
    public var isEmpty: Bool { paragraphs.isEmpty }

    public var pageCount: Int { pages.count }

    // MARK: - The lines composed

    /// The line a number names, which has to be one already composed.
    func line(_ number: Int) -> ColumnComposer.Line { run[number - runStart] }

    /// The chapter's first line, once the paragraph it stands in has been composed.
    var firstLine: Int? { composed.lowerBound == 0 && !run.isEmpty ? runStart : nil }

    /// The number past the chapter's last line, once the paragraph it ends has been composed.
    var endLine: Int? { composed.upperBound == paragraphs.count && !run.isEmpty ? runStart + run.count : nil }

    private var runEnd: Int { runStart + run.count }

    /// Composes the paragraphs asked for, and every one between them and what already is.
    private func compose(_ wanted: Range<Int>) async {
        let previous = composing
        let task = Task { [self] in
            await previous?.value
            await extend(to: wanted.clamped(to: 0 ..< paragraphs.count))
        }

        composing = task
        await task.value
    }

    private func extend(to wanted: Range<Int>) async {
        guard !wanted.isEmpty else { return }

        if composed.isEmpty {
            composed = wanted.lowerBound ..< wanted.lowerBound
            append(await setter.lines(of: Array(paragraphs[wanted])))
            return
        }

        if wanted.lowerBound < composed.lowerBound {
            prepend(await setter.lines(of: Array(paragraphs[wanted.lowerBound ..< composed.lowerBound])))
        }

        if wanted.upperBound > composed.upperBound {
            append(await setter.lines(of: Array(paragraphs[composed.upperBound ..< wanted.upperBound])))
        }
    }

    private func append(_ groups: [[ColumnComposer.Line]]) {
        for group in groups {
            paragraphStarts.append(runEnd)
            run += group
        }

        composed = composed.lowerBound ..< composed.upperBound + groups.count
        noteTheTitle()
    }

    private func prepend(_ groups: [[ColumnComposer.Line]]) {
        var number = runStart - groups.reduce(0) { $0 + $1.count }
        var starts: [Int] = []

        runStart = number

        for group in groups {
            starts.append(number)
            number += group.count
        }

        run.insert(contentsOf: groups.joined(), at: 0)
        paragraphStarts.insert(contentsOf: starts, at: 0)
        composed = composed.lowerBound - groups.count ..< composed.upperBound
        noteTheTitle()
    }

    /// Works out how much of the air above the chapter's first line it gives up at the head of a page.
    ///
    /// A title keeps its air by standing in it, and at the top of a page there is nothing above it to
    /// stand clear of: the eight lines a chapter keeps would push its title well down its own opening
    /// page. Two are left, so the title is not hard against the top edge.
    private func noteTheTitle() {
        guard let first = firstLine else { return }

        let air = line(first).titleAir

        titleTrim = air - min(air, TitleBlock.atTheTopOfAPage * context.style.pageLine)
    }

    /// Composes forward from line `start` until `depth` of lines stand there, or the chapter ends.
    private func compose(from start: Int, covering depth: CGFloat) async {
        while composed.upperBound < paragraphs.count, self.depth(of: start ..< runEnd) < depth {
            await compose(composed.lowerBound ..< composed.upperBound + batch(from: composed.upperBound, by: 1))
        }
    }

    /// Composes backward from line `limit` until `depth` of lines stand before it, or the chapter starts.
    private func compose(to limit: Int, covering depth: CGFloat) async {
        while composed.lowerBound > 0, self.depth(of: runStart ..< limit) < depth {
            await compose(composed.lowerBound - batch(from: composed.lowerBound - 1, by: -1) ..< composed.upperBound)
        }
    }

    /// How many paragraphs from `first` hold about a page of text, counting in the direction `step` goes.
    private func batch(from first: Int, by step: Int) -> Int {
        let style = context.style
        let perLine = max(1, context.textSize.width / (style.fontSize * Self.averageAdvance))
        let perPage = Int(perLine * max(1, context.textSize.height / style.pageLine))
        var characters = 0
        var index = first
        var count = 0

        while paragraphs.indices.contains(index), characters < perPage {
            characters += paragraphs[index].length
            count += 1
            index += step
        }

        return max(1, count)
    }

    /// How wide a character of running text is, against the type size. Only for guessing how many
    /// paragraphs make a page; the guess is checked against the lines composed.
    private static let averageAdvance: CGFloat = 0.5

    private func depth(of numbers: Range<Int>) -> CGFloat {
        numbers.reduce(CGFloat(0)) { $0 + line($1).height }
    }

    // MARK: - Cutting a page

    /// How deep the stretch the cutter looks over runs: the page and the pages it is weighed against.
    private func horizon(for room: CGFloat) -> CGFloat { room + PageCutter.lookahead * context.textSize.height }

    /// The line that stands at a reading position, composing the paragraph it is in.
    func line(at position: Int) async -> Int? {
        guard !paragraphs.isEmpty else { return nil }

        let laidOut = laidOutOffset(max(0, position))
        let paragraph = paragraphIndex(containing: laidOut)

        await compose(paragraph ..< paragraph + 1)

        let numbers = lines(of: paragraph)

        return numbers.first { laidOut < NSMaxRange(line($0).characters) } ?? numbers.last ?? nearestLine(to: paragraph)
    }

    /// The chapter's first line, composing the paragraphs at its head until one gives any.
    func openingLine() async -> Int? {
        var count = 1

        while firstLine == nil, count <= paragraphs.count {
            await compose(0 ..< count)
            count += 1
        }

        return firstLine
    }

    /// The number past the chapter's last line, composing the paragraphs at its end until one gives any.
    func closingLine() async -> Int? {
        var count = 1

        while endLine == nil, count <= paragraphs.count {
            await compose(paragraphs.count - count ..< paragraphs.count)
            count += 1
        }

        return endLine
    }

    /// The page that starts at line `start`, `top` points down the text.
    ///
    /// - Parameter opens: the page opens on the chapter's title, so the air above the title can go.
    func page(from start: Int, top: CGFloat, opens: Bool) async -> Page {
        await compose(from: start, covering: horizon(for: context.textSize.height - top))

        return cut(from: start, top: top, opens: opens)
    }

    /// The page that ends just before line `limit`, `room` deep.
    ///
    /// - Parameter opens: where the page turns out to open the chapter, it opens it at the top of a
    ///   page rather than under the end of the chapter before.
    func page(to limit: Int, room: CGFloat, opens: Bool) async -> Page {
        await compose(to: limit, covering: horizon(for: room))

        return cut(to: limit, room: room, opens: opens)
    }

    private func cut(from start: Int, top: CGFloat, opens: Bool) -> Page {
        let room = context.textSize.height - top
        var reach = start
        var covered: CGFloat = 0

        while reach < runEnd, covered < horizon(for: room) {
            covered += line(reach).height
            reach += 1
        }

        let cutting = cutter(over: start ..< reach, trimsTitle: opens)
        let limit = cutting.end(from: 0, room: room)
        let page = cutting.page(
            0 ..< limit,
            room: room,
            endsTheChapter: cutting.reachesEnd && limit == cutting.slugs.count,
            opensTheChapter: false
        )

        return placed(page, from: start, top: top, trimsTitle: opens && start == firstLine)
    }

    private func cut(to limit: Int, room: CGFloat, opens: Bool) -> Page {
        var from = limit
        var covered: CGFloat = 0

        while from > runStart, covered < horizon(for: room) {
            from -= 1
            covered += line(from).height
        }

        // The line after the page comes along where there is one, so the break at its foot can be judged.
        let past = limit < runEnd ? limit + 1 : limit
        let cutting = cutter(over: from ..< past, trimsTitle: opens)
        let local = limit - from
        let start = cutting.start(to: local, room: room)
        let opensTheChapter = cutting.reachesStart && start == 0
        let page = cutting.page(
            start ..< local,
            room: room,
            endsTheChapter: limit == endLine,
            opensTheChapter: opensTheChapter
        )

        return placed(page, from: from, top: 0, trimsTitle: opens && opensTheChapter)
    }

    /// A cutter over a stretch of composed lines.
    private func cutter(over numbers: Range<Int>, trimsTitle: Bool) -> PageCutter {
        let style = context.style
        var slugs = numbers.map { line($0).slug }

        if trimsTitle, let first = firstLine, numbers.contains(first) {
            slugs[first - numbers.lowerBound].height -= titleTrim
            slugs[first - numbers.lowerBound].leastHeight -= titleTrim
        }

        return PageCutter(
            slugs: slugs,
            depth: context.textSize.height,
            pageLine: style.pageLine,
            referenceLineHeight: max(1, style.fontSize + style.lineSpacing),
            reachesEnd: numbers.upperBound == endLine,
            reachesStart: numbers.lowerBound == firstLine
        )
    }

    /// A page the cutter made over a stretch starting at line `base`, as it stands in the chapter.
    private func placed(_ cut: Page, from base: Int, top: CGFloat, trimsTitle: Bool) -> Page {
        var page = cut

        page.lines = cut.lines.lowerBound + base ..< cut.lines.upperBound + base
        page.top = cut.top + top
        page.plate = cut.plate.map { Page.Plate(line: $0.line + base, height: $0.height) }
        page.trimsTitle = trimsTitle
        return page
    }

    /// Every page of the chapter, cut one after another from its first line.
    private func cutWhole(top: CGFloat) -> [Page] {
        guard let first = firstLine, let end = endLine else { return [] }

        var pages: [Page] = []
        var start = first
        var top = top

        while start < end {
            let page = cut(from: start, top: top, opens: start == first && top == 0)

            pages.append(page)
            start = page.lines.upperBound
            top = 0
        }

        return pages
    }

    /// The same lines standing somewhere else on a page: at their own spacing, from `top` down.
    ///
    /// A chapter's opening cut from behind is made to stand on a page of its own, and is moved down
    /// under the end of the chapter before it where the two share the page instead.
    func moved(_ page: Page, to top: CGFloat) -> Page {
        var moved = page

        moved.top = top
        moved.leading = 0
        moved.imagePadding = 0
        moved.trimsTitle = false
        return moved
    }

    /// True where a page carries the chapter's last line.
    func ends(_ page: Page) -> Bool { page.lines.upperBound == endLine }

    /// True where a page carries the chapter's first line.
    func opens(_ page: Page) -> Bool { page.lines.lowerBound == firstLine }

    /// How far down the text a page's lines reach, the room above them included.
    public func bottom(of page: Page) -> CGFloat {
        let depths = page.lines.reduce(CGFloat(0)) { total, number in
            total + depth(of: number, on: page) + (line(number).image != nil ? page.imagePadding * 2 : 0)
        }

        return page.top + depths + CGFloat(max(0, page.lines.count - 1)) * page.leading
    }

    /// How deep a line stands on a page: less than its own for the plate that gave some up, or for the
    /// title that left its air above the top of the page.
    func depth(of number: Int, on page: Page) -> CGFloat {
        if let plate = page.plate, plate.line == number { return plate.height }

        return line(number).height - trim(of: number, on: page)
    }

    /// Where a line's baseline stands below its own top on a page.
    func baseline(of number: Int, on page: Page) -> CGFloat {
        line(number).baseline - trim(of: number, on: page)
    }

    private func trim(of number: Int, on page: Page) -> CGFloat {
        page.trimsTitle && number == page.lines.lowerBound && number == firstLine ? titleTrim : 0
    }

    /// How large the picture on a line is drawn. What the line gave up the picture gave up, the spacing
    /// under it being no part of the picture, and the width follows so the plate keeps its shape.
    func pictureSize(of number: Int, on page: Page) -> CGSize {
        let natural = line(number).imageSize
        let given = line(number).height - depth(of: number, on: page)

        guard given > 0, natural.height > 0 else { return natural }

        let height = max(1, natural.height - given)

        return CGSize(width: natural.width * (height / natural.height), height: height)
    }

    // MARK: - Paragraphs and positions

    private func paragraphIndex(containing laidOut: Int) -> Int {
        var low = 0
        var high = paragraphs.count - 1

        while low < high {
            let middle = (low + high + 1) / 2

            if paragraphs[middle].location <= laidOut { low = middle } else { high = middle - 1 }
        }

        return low
    }

    /// The numbers of a composed paragraph's lines.
    private func lines(of paragraph: Int) -> Range<Int> {
        guard composed.contains(paragraph) else { return runStart ..< runStart }

        let index = paragraph - composed.lowerBound
        let end = index + 1 < paragraphStarts.count ? paragraphStarts[index + 1] : runEnd

        return paragraphStarts[index] ..< end
    }

    /// The first line at or after a paragraph that gave none of its own.
    private func nearestLine(to paragraph: Int) -> Int? {
        run.isEmpty ? nil : min(max(runStart, lines(of: paragraph).lowerBound), runEnd - 1)
    }

    /// How far the chapter's own text runs, counted the way a reading position is.
    public var sourceLength: Int { sourceOffset(text.length) }

    /// Where a page starts, counted the way a reading position is.
    public func startOffset(of page: Page) -> Int { sourceOffset(line(page.lines.lowerBound).characters.location) }

    /// Where a page stops, counted the way a reading position is.
    public func endOffset(of page: Page) -> Int {
        sourceOffset(NSMaxRange(line(page.lines.upperBound - 1).characters))
    }

    /// Which of the pages of a chapter laid out whole a reading position falls on.
    public func pageIndex(containing position: Int) -> Int {
        let laidOut = laidOutOffset(position)

        return pages.firstIndex { NSLocationInRange(laidOut, range(of: $0)) } ?? max(0, pages.count - 1)
    }

    /// The stretch of the text a page covers.
    func range(of page: Page) -> NSRange {
        let first = line(page.lines.lowerBound).characters
        let last = line(page.lines.upperBound - 1).characters

        return NSRange(location: first.location, length: NSMaxRange(last) - first.location)
    }

    /// A position is counted in the text as it arrived, not in the text as it was set.
    ///
    /// Justified text carries a soft hyphen at every break the dictionary allows, roughly one character
    /// in eight. Counting those would move a stored position whenever the alignment changed, which is
    /// the one thing a stored position must never do.
    private func sourceOffset(_ laidOut: Int) -> Int {
        let bounded = min(max(0, laidOut), text.length)

        return bounded - hyphens(before: bounded)
    }

    /// The first place in the set text where `source` characters of the text as it arrived stand behind.
    private func laidOutOffset(_ source: Int) -> Int {
        var low = max(0, min(source, text.length))
        var high = min(text.length, max(0, source) + softHyphens.count)

        while low < high {
            let middle = (low + high) / 2

            if sourceOffset(middle) < source { low = middle + 1 } else { high = middle }
        }

        return low
    }

    private func hyphens(before laidOut: Int) -> Int {
        var low = 0
        var high = softHyphens.count

        while low < high {
            let middle = (low + high) / 2

            if softHyphens[middle] < laidOut { low = middle + 1 } else { high = middle }
        }

        return low
    }

    private static func softHyphens(in string: NSString) -> [Int] {
        (0 ..< string.length).filter { string.character(at: $0) == softHyphen }
    }

    private static let softHyphen = unichar(0x00AD)

    // MARK: - What the reader asks for

    /// One line as the column set it.
    ///
    /// A justified line that does not end its paragraph is meant to reach the measure exactly, so this
    /// is what a test reads to say whether it did.
    public struct TypesetLine {
        public var text: String
        /// Where the line starts across the measure, which a quoted passage holds off the edge.
        public var origin: CGFloat
        /// Where the line ends across the measure, counted from the same edge as ``origin``.
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

    /// The lines that fall on a page, in the order they were set.
    public func typesetLines(on page: Page) -> [TypesetLine] {
        page.lines.map { number in
            var typeset = described(line(number))

            typeset.height = depth(of: number, on: page)
            typeset.baseline = baseline(of: number, on: page)
            return typeset
        }
    }

    /// Every line of the chapter composed so far, in the order it was set.
    public var typesetLines: [TypesetLine] { run.map { described($0) } }

    private func described(_ line: ColumnComposer.Line) -> TypesetLine {
        TypesetLine(
            text: (text.string as NSString).substring(with: line.characters),
            origin: line.origin,
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
    public func bodyLineCount(on page: Page) -> Int {
        page.lines.count { !line($0).isHeading }
    }

    /// A line's CoreText line, set from the chapter's own text the first time anything asks for it.
    func drawnLine(_ number: Int) -> CTLine? {
        if let held = drawnLines[number] { return held }

        guard
            let setting = line(number).setting,
            let built = ParagraphRuler.line(in: text, setting: setting)
        else { return nil }

        drawnLines[number] = built
        return built
    }

    /// Draws a page, line by line, so the page's own leading can be applied as it goes.
    ///
    /// The text matrix is flipped because a UIKit context counts downwards and CoreText sets glyphs
    /// upwards; without it every line draws on its head.
    public func draw(_ page: Page) {
        guard let drawing = UIGraphicsGetCurrentContext() else { return }

        var cursor = context.textRect.minY + page.top

        drawing.saveGState()
        drawing.textMatrix = CGAffineTransform(scaleX: 1, y: -1)

        for number in page.lines {
            let line = self.line(number)

            if let picture = line.image {
                // The picture is centred in everything the page gave it, its own line's spacing
                // included, so what stands above it matches what stands below.
                let size = pictureSize(of: number, on: page)
                let allotted = depth(of: number, on: page) + page.imagePadding * 2
                let top = cursor + (allotted - size.height) / 2
                // Centred on the measure rather than on where it was set, since a plate that gave up
                // depth gave up width with it.
                let left = context.textRect.minX + (context.textSize.width - size.width) / 2

                picture.draw(
                    in: CGRect(origin: CGPoint(x: left, y: top), size: size),
                    palette: context.style.palette,
                    into: drawing
                )
                cursor += allotted + page.leading
                continue
            }

            if let drawn = drawnLine(number) {
                drawing.textPosition = CGPoint(
                    x: context.textRect.minX + line.origin,
                    y: cursor + baseline(of: number, on: page)
                )
                CTLineDraw(drawn, drawing)
            }

            cursor += depth(of: number, on: page) + page.leading
        }

        drawing.restoreGState()
    }

    /// The note whose marker stands under a point on a page, in the page's own coordinates.
    ///
    /// Walked the same way the page is drawn, so what a finger finds is what the reader can see. The
    /// marker carries the note on its own glyph run, which saves counting characters back through the
    /// soft hyphens the line was set with.
    public func note(at point: CGPoint, on page: Page) -> NoteHit? {
        guard
            let placed = placedLines(on: page).first(where: { point.y >= $0.edge && point.y < $0.edge + $0.height }),
            let drawn = drawnLine(placed.index)
        else { return nil }

        let origin = context.textRect.minX + line(placed.index).origin

        guard let found = note(at: point.x - origin, in: drawn) else { return nil }

        return NoteHit(
            id: found.id,
            rect: CGRect(x: origin + found.start, y: placed.edge, width: found.width, height: placed.height)
        )
    }

    /// The link a finger found on a page, or nothing where it landed on ordinary words.
    public func link(at point: CGPoint, on page: Page) -> LinkHit? {
        guard
            let placed = placedLines(on: page).first(where: { point.y >= $0.edge && point.y < $0.edge + $0.height }),
            let drawn = drawnLine(placed.index)
        else { return nil }

        let origin = context.textRect.minX + line(placed.index).origin

        guard let found = link(at: point.x - origin, in: drawn) else { return nil }

        return LinkHit(
            target: found.target,
            rect: CGRect(x: origin + found.start, y: placed.edge, width: found.width, height: placed.height)
        )
    }

    /// A link found in a line: where it points, and where along the line its words stand.
    private struct FoundLink {
        var target: String
        var start: CGFloat
        var width: CGFloat
    }

    /// A link runs across a phrase rather than standing on one glyph, so what is asked is whether the
    /// finger fell inside its words rather than how near it came to their middle.
    private func link(at distance: CGFloat, in line: CTLine) -> FoundLink? {
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { return nil }

        for glyphs in runs {
            let attributes = CTRunGetAttributes(glyphs) as NSDictionary

            guard let target = attributes[NSAttributedString.Key.bookLink] as? String else { continue }

            let width = CGFloat(CTRunGetTypographicBounds(glyphs, CFRange(location: 0, length: 0), nil, nil, nil))
            let start = CTLineGetOffsetForStringIndex(line, CTRunGetStringRange(glyphs).location, nil)

            if distance >= start, distance <= start + width {
                return FoundLink(target: target, start: start, width: width)
            }
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
    public func notes(on page: Page) -> [String] {
        var result: [String] = []

        for number in page.lines {
            guard let runs = drawnLine(number).flatMap({ CTLineGetGlyphRuns($0) as? [CTRun] }) else { continue }

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

    /// The chapter's own words over a stretch of it, counted the way a reading position and a mark are.
    ///
    /// Exactly what an offset skips comes out, and nothing else: a character an offset counts has to
    /// stand in this text, or a mark found here lands somewhere else on the page. The word joiners the
    /// binder put in are counted, so they stay, and folding drops them before anything is matched.
    public func sourceText(in range: Range<Int>) -> String {
        let string = text.string as NSString
        let start = laidOutOffset(max(0, range.lowerBound))
        let end = laidOutOffset(max(0, range.upperBound))

        guard start < end, end <= string.length else { return "" }

        return string.substring(with: NSRange(location: start, length: end - start))
            .replacingOccurrences(of: String(Typography.softHyphen), with: "")
    }

    /// The whole chapter as the book wrote it, for finding a passage in it again.
    public var sourceText: String { sourceText(in: 0 ..< sourceLength) }

    /// A place in the text as it was set, counted the way a reading position and a mark are.
    public func position(ofLaidOut offset: Int) -> Int { sourceOffset(offset) }

    /// The other way: a stretch counted as a reading position, as it stands in the text as it was set.
    public func laidOutRange(of range: Range<Int>) -> NSRange {
        let start = laidOutOffset(max(0, range.lowerBound))
        let end = laidOutOffset(max(0, range.upperBound))

        return NSRange(location: start, length: max(0, end - start))
    }

    /// The line a position stands on, where that line stands on a page.
    ///
    /// A position between two lines takes the one after it, so a mark made at the head of a paragraph
    /// stands against its first line rather than against the end of the paragraph before.
    public func line(atPosition position: Int, on page: Page) -> PlacedLine? {
        let laidOut = laidOutOffset(position)
        let placed = placedLines(on: page)

        return placed.first { NSLocationInRange(laidOut, line($0.index).characters) }
            ?? placed.first { laidOut <= line($0.index).characters.location }
    }

    /// The page's text, for VoiceOver and for the reader's own accessibility label.
    public func pageText(_ page: Page) -> String {
        // Without stripping them, VoiceOver reads a page full of soft hyphens. A picture is drawn and
        // so invisible to it, and is named instead: the page says one is there rather than skipping it.
        (text.string as NSString)
            .substring(with: range(of: page))
            .replacingOccurrences(of: String(Typography.softHyphen), with: "")
            .replacingOccurrences(of: "\u{2060}", with: "")
            .replacingOccurrences(
                of: String(ChapterPagination.pictureMark),
                with: String(localized: "Picture.", bundle: .module)
            )
    }
}
