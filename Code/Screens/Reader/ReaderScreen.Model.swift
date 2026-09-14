//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import AuthorTodayBooks
import BookKit
import BookRenderer
import BookStorage
import Foundation
import UIKit

extension ReaderScreen {
    @Observable @MainActor
    final class Model {
        /// Where to land once a chapter is laid out.
        enum PageAnchor: Equatable {
            case first
            /// A page counted from the start of the chapter's own text.
            case page(Int)
            /// The character the reader stopped on, which survives a change of font.
            case offset(Int)
        }

        /// One chapter's page, drawn as part of a reader's page. A page carries two of these where a
        /// chapter runs on from the end of the one before it.
        struct Piece: Identifiable {
            let layout: ChapterLayout
            let page: Int

            var id: String { "\(layout.chapterId).\(page)" }
        }

        /// What the reader draws at a given place in the book.
        enum Page {
            case title
            case text([Piece])
            case blank

            var isText: Bool {
                guard case .text = self else { return false }

                return true
            }

            var isTitle: Bool {
                guard case .title = self else { return false }

                return true
            }
        }

        let workId: Int
        let workTitle: String

        private(set) var book: Book?
        private(set) var chapters: [BookChapter] = []
        private(set) var currentChapterId: Int?
        private(set) var layout: ChapterLayout?
        private(set) var isLoading = false
        private(set) var errorMessage: String?

        /// True when the last request to the service failed and the reader is running off the device.
        private(set) var isOffline = false

        /// The stretches of this book the reader marked.
        private(set) var bookmarks: [Bookmark] = []

        /// How far a long chapter has got through being laid out, `0…1`. Short chapters never set it:
        /// they are done before a reader could read a progress bar.
        private(set) var paginationProgress: Double?

        /// What the page calls the book: its own name, with whatever its series writes into every one of
        /// its titles taken off. The same name the shelf gives it, and the title page names the series
        /// under it anyway.
        var bookTitle: String {
            guard let book else { return workTitle }

            return SeriesNumbering.title(book.title, in: book.seriesTitle, volume: book.seriesOrder)
        }

        /// True from the tap that opens a book to its first page being set.
        ///
        /// Fetching a chapter and measuring the book behind it are two jobs to the reader's model and
        /// one wait to whoever is waiting, so one card covers both.
        var isOpening: Bool { paginationProgress != nil || (isLoading && layout == nil) }

        var currentPage = 0 {
            didSet {
                guard currentPage != oldValue else { return }

                savePosition()
                reportProgress()
            }
        }

        @ObservationIgnored
        private let session: SessionStore

        @ObservationIgnored
        private let store: SQLiteBookStore

        @ObservationIgnored
        private let processor: BookProcessor

        @ObservationIgnored
        private let inbox: BookInbox

        @ObservationIgnored
        private var context: ChapterLayout.Context?

        /// Chapters laid out for the current context: the one on screen and the ones either side of it.
        ///
        /// Observed, not ignored: a page shows the chapter that starts on it as well as the one that
        /// ends there, so a neighbour arriving has to redraw the page the reader is looking at.
        private var layouts: [Int: ChapterLayout] = [:]

        @ObservationIgnored
        private var parsed: [Int: ChapterContent] = [:]

        @ObservationIgnored
        private var prefetch: Task<Void, Never>?

        /// Where every chapter of this book begins, for the style and page size now in force.
        @ObservationIgnored
        private var pagination: BookPagination?
        /// Where each chapter starts in the book and how long the book runs, kept between passes.
        private var paging = BookPaging.nothing

        @ObservationIgnored
        private var paginating: Task<Void, Never>?

        /// The pass measuring the rest of the book behind the reader.
        @ObservationIgnored
        private var backgroundMeasuring: Task<Void, Never>?

        /// Nothing heavy runs before this moment. Pushed forward by every page turn.
        @ObservationIgnored
        private var quietUntil: Date = .distantPast

        @ObservationIgnored
        private var sessionId: String?

        @ObservationIgnored
        private var requestedChapterId: Int?

        @ObservationIgnored
        private var hasLoaded = false

        @ObservationIgnored
        private var pendingAnchor: PageAnchor = .first

        @ObservationIgnored
        private var lastReportedProgress: Double = -1

        /// The chapter the last position was written against, so a move to another one is written
        /// through rather than waited on.
        @ObservationIgnored
        private var wroteChapterId: Int?

        @ObservationIgnored
        private var positionSaver: Task<Void, Never>?

        init(
            workId: Int,
            workTitle: String,
            initialChapterId: Int?,
            session: SessionStore,
            store: SQLiteBookStore = .shared,
            processor: BookProcessor = .shared,
            inbox: BookInbox = .shared
        ) {
            self.workId = workId
            self.workTitle = workTitle
            self.requestedChapterId = initialChapterId
            self.session = session
            self.store = store
            self.processor = processor
            self.inbox = inbox
        }

        // MARK: - Where the reader is

        var readableChapters: [BookChapter] { chapters.filter(\.isReadable) }

        private var currentIndex: Int? {
            readableChapters.firstIndex { $0.id == currentChapterId }
        }

        var previousChapter: BookChapter? {
            guard let index = currentIndex, index > 0 else { return nil }

            return readableChapters[index - 1]
        }

        var nextChapter: BookChapter? {
            guard let index = currentIndex, index + 1 < readableChapters.count else { return nil }

            return readableChapters[index + 1]
        }

        var chapterTitle: String? {
            readableChapters.first { $0.id == currentChapterId }?.displayTitle
        }

        /// The book's own title page opens the first chapter, and nothing else.
        var hasTitlePage: Bool { currentIndex == 0 }

        private var titlePageCount: Int { hasTitlePage ? 1 : 0 }

        var pageCount: Int { (layout?.pageCount ?? 0) + titlePageCount }

        var hasPageBefore: Bool { previousChapter != nil }

        var hasPageAfter: Bool { nextChapter != nil }

        /// How many pages stand side by side on one sheet. Told by the view, which is the only thing
        /// that knows how much room the window has, and never below one.
        private(set) var columns = 1

        /// How many sheets the chapter comes to, a sheet being what one turn moves.
        var sheetCount: Int { Int((Double(pageCount) / Double(columns)).rounded(.up)) }

        /// Which sheet the reader is on. Setting it opens that sheet at its first page.
        var currentSheet: Int {
            get { currentPage / columns }
            set { currentPage = newValue * columns }
        }

        /// The pages in front of the reader: one, or a spread of two.
        var pagesOnScreen: [Int] { pages(onSheet: currentSheet) }

        /// Whether a sheet takes the book's title above it.
        ///
        /// Every sheet of text does. One carrying the book's own title page takes none, since that page
        /// already says what the book is called, and one carrying no text has nothing to name.
        func showsTitle(onSheet sheet: Int) -> Bool {
            let standing = pages(onSheet: sheet).map(page(at:))

            return standing.contains(where: \.isText) && !standing.contains(where: \.isTitle)
        }

        /// Which page stands in one column of the sheet the reader is on.
        func page(inColumn column: Int) -> Int {
            let pages = pagesOnScreen

            return pages.indices.contains(column) ? pages[column] : currentPage
        }

        /// Which of this chapter's pages each column of a sheet shows.
        ///
        /// Inside the chapter a sheet is the next `columns` pages of its own grid. The sheets either
        /// side belong to the chapters either side and are counted on *their* grids, so a turn that
        /// crosses out of this chapter lands on the very sheet it had already brought in.
        func pages(onSheet sheet: Int) -> [Int] {
            if sheet < 0, let before = beforeThisPage() {
                return pages(from: -1 - (before.page % columns))
            }

            if sheet >= sheetCount, let beyond = beyondThisPage() {
                return pages(from: pageCount - (beyond.page % columns))
            }

            return pages(from: sheet * columns)
        }

        /// A sheet's worth of pages, counting up from its first.
        private func pages(from first: Int) -> [Int] { (0 ..< columns).map { first + $0 } }

        private func textIndex(for page: Int) -> Int { page - titlePageCount }

        /// Where the reader is, as an offset to keep.
        ///
        /// The title page stands before the chapter's own text and has no offset in it, and the offset
        /// that stands for the start of that text is the page after it. So it is kept as one below the
        /// start, an offset never being negative otherwise: kept as nought, a book closed on its title
        /// page reopened on the page after it, every time.
        private var storedOffset: Int {
            let page = textIndex(for: currentPage)

            guard page >= 0 else { return Self.titlePageOffset }

            return layout?.characterOffset(ofPage: page) ?? 0
        }

        /// What the title page is kept as, being the one page with no text of its own behind it.
        static let titlePageOffset = -1

        /// What sits at `index`, which runs from `-1` to ``pageCount`` so a turn can show the page in the
        /// neighbouring chapter it is about to land on.
        /// The language the chapter on screen was read as, which is what settles its alignment.
        var chapterLanguage: String? {
            currentChapterId.flatMap { parsed[$0]?.language }
        }

        /// True where the chapter on screen is written from the right, which turns its pages that way.
        var readsRightToLeft: Bool {
            currentChapterId.flatMap { parsed[$0]?.readsRightToLeft } ?? false
        }

        /// Every line on the page as it was set, for a debug report.
        var pageLines: [ChapterLayout.TypesetLine] {
            switch page(at: currentPage) {
                case let .text(pieces): pieces.flatMap { $0.layout.typesetLines(onPage: $0.page) }
                default: []
            }
        }

        /// The text the page is showing, for a debug report.
        var pageText: String {
            switch page(at: currentPage) {
                case .title: workTitle
                case let .text(pieces): pieces.map { $0.layout.pageText($0.page) }.joined(separator: "\n")
                case .blank: ""
            }
        }

        /// The markup the chapter arrived in, for a report about how something in it was set.
        ///
        /// The paragraphs say what the reader made of the chapter; only the markup says what it was
        /// given, which is the difference that matters when a marker was not recognised as one.
        func chapterMarkup() async -> String? {
            guard let currentChapterId else { return nil }

            return await store.body(workId: workId, chapterId: currentChapterId)?.html
        }

        // MARK: - Text picked off the page

        /// Text the reader has drawn a finger across, and where it stands on the page.
        struct PickedText: Identifiable {
            let selection: ChapterLayout.Selection
            /// One box per line it runs through, for painting under it.
            let rects: [CGRect]
            /// Which page of the spread the words were taken off, so what is drawn over them and what
            /// is hung beside them both land on that page rather than on the sheet's first.
            let page: Int

            var id: String { "\(selection.range.location).\(selection.range.length)" }
        }

        private(set) var picked: PickedText?

        /// Folding a chapter costs a pass over all of it, and every redraw asks where its marks stand.
        @ObservationIgnored
        private var foldedChapters: [Int: BookSearch.Folded] = [:]

        /// Picks out everything between two points on one page, out to whole words.
        func pickOut(from start: CGPoint, to finish: CGPoint, onPage index: Int) {
            guard case let .text(pieces) = page(at: index) else { return }

            for piece in pieces {
                guard let range = piece.layout.words(from: start, to: finish, onPage: piece.page) else { continue }

                let chosen = piece.layout.selection(of: range)

                guard !chosen.isEmpty else { continue }

                picked = PickedText(
                    selection: chosen,
                    rects: piece.layout.rects(of: range, onPage: piece.page),
                    page: index
                )
                return
            }
        }

        func clearPicked() { picked = nil }

        // MARK: - Bookmarks

        /// One stretch of one chapter standing in front of the reader.
        private struct Shown {
            let chapterId: Int
            let start: Int
            let end: Int
        }

        /// What the reader can see, chapter by chapter. A page carries two stretches where a chapter
        /// runs on from the end of the one before it, and a spread carries whatever both its pages do.
        private var displayedRanges: [Shown] {
            pagesOnScreen.flatMap(ranges(onPage:))
        }

        private func ranges(onPage index: Int) -> [Shown] {
            guard case let .text(pieces) = page(at: index) else { return [] }

            return pieces.map { piece in
                let start = piece.layout.characterOffset(ofPage: piece.page)
                let end =
                    piece.page + 1 < piece.layout.pageCount
                    ? piece.layout.characterOffset(ofPage: piece.page + 1)
                    : piece.layout.sourceLength

                return Shown(chapterId: piece.layout.chapterId, start: start, end: max(end, start + 1))
            }
        }

        /// The marks the page in front of the reader stands on.
        var bookmarksOnPage: [Bookmark] {
            let ranges = displayedRanges

            return bookmarks.filter { mark in
                let place = place(of: mark)

                return ranges.contains { shown in
                    mark.chapterId == shown.chapterId
                        && place.lowerBound < max(shown.end, shown.start + 1)
                        && shown.start < max(place.upperBound, place.lowerBound + 1)
                }
            }
        }

        /// Where a mark stands in the chapter as it reads now, which is where its words are.
        ///
        /// A mark carrying none falls back to the offsets it was written with, which is what it always
        /// did, and a chapter nothing has laid out yet has no text to look in.
        func place(of mark: Bookmark) -> Range<Int> {
            guard
                let chapter = folded(mark.chapterId)
            else {
                return mark.startOffset ..< max(mark.endOffset, mark.startOffset + 1)
            }

            return mark.place(in: chapter)
        }

        /// A chapter's text folded for finding a mark in it, kept so a redraw does not fold it again.
        private func folded(_ chapterId: Int) -> BookSearch.Folded? {
            if let held = foldedChapters[chapterId] { return held }

            guard let built = layouts[chapterId] else { return nil }

            let made = BookSearch.fold(built.sourceText)

            foldedChapters[chapterId] = made
            return made
        }

        var isPageBookmarked: Bool { !bookmarksOnPage.isEmpty }

        /// True where the page in front of the reader is one a mark can stand on.
        ///
        /// A mark covers a stretch of a chapter's text, so a page carrying none of it can hold none.
        /// The title page a book opens on is the one such page a reader meets.
        var canBookmarkPage: Bool { !displayedRanges.isEmpty }

        /// Marks what the reader can see, or clears every mark it stands on.
        func toggleBookmark() {
            let standing = bookmarksOnPage

            guard standing.isEmpty else { return remove(standing) }

            let made = displayedRanges.map { shown in
                let bare = Bookmark(
                    workId: workId,
                    chapterId: shown.chapterId,
                    startOffset: shown.start,
                    endOffset: shown.end,
                    createdAt: .now
                )

                guard let built = layouts[shown.chapterId] else { return bare }

                return words(for: bare, in: built, of: BookSearch.fold(built.sourceText)) ?? bare
            }

            bookmarks.append(contentsOf: made)

            Task { [store] in
                for mark in made { await store.store(bookmark: mark) }
            }
        }

        /// Gives a mark written before marks kept any the words it stands on.
        ///
        /// Done as the chapter is laid out, since the layout is the only thing that counts a position
        /// the way a mark does: the text a page is set from carries the word joiners the binder put in,
        /// and an offset counts those. A mark already carrying words is left alone.
        ///
        /// What it cannot do is undo a reading that has already moved the offsets under it. Those marks
        /// are wrong before this runs and stay wrong after it, and the words it writes down are the
        /// words they point at now. What it buys them is that they stop moving: a mark that knows its
        /// own words is found by them, and no later reading of the book can shift it again.
        private func rememberWords(in built: ChapterLayout) {
            let standing = bookmarks.filter { $0.chapterId == built.chapterId && $0.text == nil }

            guard !standing.isEmpty else { return }

            let whole = BookSearch.fold(built.sourceText)
            let written = standing.compactMap { mark in words(for: mark, in: built, of: whole) }

            guard !written.isEmpty else { return }

            for mark in written {
                guard let at = bookmarks.firstIndex(where: { $0.id == mark.id }) else { continue }

                bookmarks[at] = mark
            }

            Task { [store] in
                for mark in written { await store.store(bookmark: mark) }
            }
        }

        /// The same mark, carrying the opening of the stretch it stands on and which of those it is.
        private func words(for mark: Bookmark, in built: ChapterLayout, of whole: BookSearch.Folded) -> Bookmark? {
            let stop = min(mark.endOffset, mark.startOffset + Bookmark.wordsKept)
            let words = built.sourceText(in: mark.startOffset ..< stop)

            guard !BookSearch.fold(words).isEmpty else { return nil }

            return Bookmark(
                workId: mark.workId,
                chapterId: mark.chapterId,
                startOffset: mark.startOffset,
                endOffset: mark.endOffset,
                text: words,
                occurrence: BookSearch.occurrence(of: words, at: mark.startOffset, in: whole),
                createdAt: mark.createdAt
            )
        }

        func remove(_ marks: [Bookmark]) {
            let taken = Set(marks.map(\.id))

            bookmarks.removeAll { taken.contains($0.id) }

            Task { [store] in
                for mark in marks { await store.remove(bookmark: mark) }
            }
        }

        /// A chapter's own marks, in the order they stand in it.
        func bookmarks(inChapter id: Int) -> [Bookmark] {
            bookmarks.filter { $0.chapterId == id }.sorted { $0.startOffset < $1.startOffset }
        }

        /// How long a chapter's text runs, for saying how far into it a mark stands.
        func length(ofChapter id: Int) -> Int? {
            layouts[id]?.sourceLength ?? chapters.first { $0.id == id }?.textLength
        }

        // MARK: - The notes the text points at

        /// A note the reader went for, and where the marker they went for stands on the page.
        struct TappedNote: Identifiable {
            let note: BookNote
            /// The marker's own box, so an aside can point at the marker rather than at the finger.
            let rect: CGRect

            var id: String { note.id }
        }

        /// The note whose marker stands under a point on the page showing, where one does.
        ///
        /// Asked before the page turns: a marker is far smaller than the turning zone it stands in,
        /// so the zone would swallow every tap meant for one.
        /// Where the reader was standing before a link took them somewhere else, while the way back is
        /// still being offered.
        private(set) var wayBack: Place?

        /// One place in the book: a chapter, and how far into its own text.
        struct Place: Equatable {
            let chapterId: Int
            let offset: Int
        }

        /// Every place the book points at, by the name its links use. Read once, in the background,
        /// since a link is as often to a chapter further on as to one already behind.
        private var places: [String: Place] = [:]
        private var isReadingPlaces = false

        /// Follows a link, remembering where it was followed from.
        func follow(_ target: String) {
            guard let place = places[target] else { return }

            wayBack = currentChapterId.map { Place(chapterId: $0, offset: storedOffset) }
            open(chapterId: place.chapterId, anchor: .offset(place.offset))
        }

        /// Goes back to where the last link was followed from, and stops offering to.
        func goBack() {
            guard let place = wayBack else { return }

            wayBack = nil
            open(chapterId: place.chapterId, anchor: .offset(place.offset))
        }

        /// Stops offering the way back, for a reader who has read on instead of taking it.
        func forgetTheWayBack() { wayBack = nil }

        /// Reads where every place the book points at stands.
        ///
        /// A link names a place rather than a chapter, so following one means knowing which chapter
        /// holds it. Nothing else in the app needs that, so it is worked out once and kept.
        func readPlaces() async {
            guard !isReadingPlaces, places.isEmpty else { return }

            isReadingPlaces = true

            defer { isReadingPlaces = false }

            for chapter in readableChapters {
                guard let content = await content(for: chapter.id) else { continue }

                var offset = 0

                for paragraph in content.paragraphs {
                    if let anchor = paragraph.anchor, places[anchor] == nil {
                        places[anchor] = Place(chapterId: chapter.id, offset: offset)
                    }

                    offset += (paragraph.text as NSString).length + 1
                }

                await Task.yield()
            }
        }

        /// The link a finger found on the page, or nothing where it landed on ordinary words.
        func link(at point: CGPoint, onPage index: Int) -> String? {
            guard case let .text(pieces) = page(at: index) else { return nil }

            for piece in pieces {
                if let found = piece.layout.link(at: point, onPage: piece.page) { return found.target }
            }

            return nil
        }

        func note(at point: CGPoint, onPage index: Int) -> TappedNote? {
            guard case let .text(pieces) = page(at: index) else { return nil }

            for piece in pieces {
                guard
                    let marker = piece.layout.note(at: point, onPage: piece.page),
                    let note = parsed[piece.layout.chapterId]?.notes[marker.id]
                else { continue }

                return TappedNote(note: note, rect: marker.rect)
            }

            return nil
        }

        /// Every note the page showing refers to, for a reader who cannot touch a marker they can't see.
        var notesOnPage: [BookNote] {
            pagesOnScreen.flatMap(notes(onPage:))
        }

        private func notes(onPage index: Int) -> [BookNote] {
            guard case let .text(pieces) = page(at: index) else { return [] }

            return pieces.flatMap { piece in
                piece.layout.notes(onPage: piece.page).compactMap { parsed[piece.layout.chapterId]?.notes[$0] }
            }
        }

        func page(at index: Int) -> Page {
            if index < 0 { return pageBefore(at: index) }

            if hasTitlePage, index == 0 { return .title }

            let page = textIndex(for: index)

            guard let layout, layout.pageRanges.indices.contains(page) else { return pageAfter(at: index) }

            return .text(pieces(of: layout, page: page))
        }

        /// Everything standing on one chapter's page: the page itself, and whichever neighbour shares it.
        ///
        /// Asked by the page the reader is on and by the pages either side of it alike, so a page is
        /// composed the same way whoever asks. Composed one way while a turn was in flight and another
        /// once it landed, the half belonging to the neighbour appeared as the turn finished.
        ///
        /// Both neighbours are taken on where the two layouts were actually set, not on where the book
        /// pass says they go: the layouts are what draw, and one set as if it started a page of its own
        /// is drawn over the chapter already on the page it shares.
        private func pieces(of built: ChapterLayout, page: Int) -> [Piece] {
            let chapters = readableChapters
            let index = chapters.firstIndex { $0.id == built.chapterId }
            var pieces: [Piece] = []

            if page == 0, let index, index > 0, let before = layouts[chapters[index - 1].id],
                    BookPagination.sharesLastPage(of: before, with: built, context: built.context) {
                pieces.append(Piece(layout: before, page: before.pageCount - 1))
            }

            pieces.append(Piece(layout: built, page: page))

            if page == built.pageCount - 1, let index, index + 1 < chapters.count,
                    let after = layouts[chapters[index + 1].id],
                    BookPagination.sharesLastPage(of: built, with: after, context: built.context) {
                pieces.append(Piece(layout: after, page: 0))
            }

            return pieces
        }

        /// The page before this chapter's first: the previous chapter's last, unless this chapter starts
        /// on that very page, in which case it is the one before that.
        private func pageBefore(at index: Int) -> Page {
            guard let before = beforeThisPage(), let neighbour = layouts[before.id] else { return .blank }

            // `-1` is the page next to this chapter, and a spread reaches one further back than that.
            let page = before.page + index + 1

            guard neighbour.pageRanges.indices.contains(page) else { return .blank }

            return .text(pieces(of: neighbour, page: page))
        }

        /// The page after this chapter's last: the next chapter's first, unless it already began on the
        /// page this chapter ended on.
        private func pageAfter(at index: Int) -> Page {
            guard
                index >= pageCount,
                let beyond = beyondThisPage(),
                let after = layouts[beyond.id]
            else { return .blank }

            let page = beyond.page + index - pageCount

            guard after.pageRanges.indices.contains(page) else { return .blank }

            return .text(pieces(of: after, page: page))
        }

        /// The footer for one page: where that page sits in its chapter, and the chapter in the book.
        ///
        /// Every page names itself rather than the reader's position, because the pages either side of
        /// this one are on screen during a turn and belong to their own chapters.
        func caption(at index: Int, expanded: Bool) -> String? {
            switch page(at: index) {
                case .title:
                    // The title page stands in front of everything, so it is page one whatever follows.
                    return caption(page: 1, of: paging.length, expanded: expanded)
                case let .text(pieces):
                    // A shared page names the chapter that starts on it: that is the news.
                    guard
                        let piece = pieces.last,
                        let page = paging.page(of: piece.layout.chapterId, within: piece.page + 1)
                    else { return nil }

                    let whole = paging.length(with: piece.layout.chapterId, measuring: piece.layout.pageCount)

                    return caption(page: page, of: whole, expanded: expanded)
                case .blank:
                    return nil
            }
        }

        /// The page alone while the reader is reading, and where it sits once they ask.
        ///
        /// A page turn is the only thing on screen with the controls away, so the footer is the figure
        /// and nothing else. Bringing the controls up is the moment the rest is worth the room.
        private func caption(page: Int, of whole: Int, expanded: Bool) -> String? {
            guard whole > 0 else { return nil }

            return expanded
                ? String(localized: "page \(page) of \(max(page, whole))")
                : page.formatted(.number)
        }

        /// Where every measured chapter begins, and how long the book is, both counted once per pass
        /// rather than on every page drawn.
        private func refreshBookPaging() {
            guard let pagination else { return paging = .nothing }

            let chapters = readableChapters
            let measured = pagination.pageCount(of: chapters)
            // A chapter that came to no pages is text the device hasn't got yet, and is guessed at with
            // the ones the pass hasn't reached.
            let (set, unset) = chapters.reduce(into: (0, 0)) { characters, chapter in
                if (pagination.placement(of: chapter.id)?.pageCount ?? 0) > 0 {
                    characters.0 += chapter.textLength ?? 0
                } else {
                    characters.1 += chapter.textLength ?? 0
                }
            }

            // The title page in front of the first chapter, which every figure counts from.
            paging = BookPaging(
                firstPages: pagination.firstPages(of: chapters).mapValues { $0 + 1 },
                chapterPages: chapters.reduce(into: [:]) { pages, chapter in
                    pages[chapter.id] = pagination.placement(of: chapter.id)?.pageCount
                },
                length: measured + BookPaging.estimate(unset, at: measured, per: set) + 1
            )
        }

        // MARK: - Layout

        /// Adopts a new page size or reading style, keeping the reader's place.
        /// Takes the shape of the page and how many of them stand on a sheet, which always move together:
        /// a spread that gained or lost a page is a page of a different width.
        func apply(context newContext: ChapterLayout.Context, columns pages: Int) {
            columns = max(1, pages)

            guard newContext.isUsable, newContext != context else { return }

            let offset = layout?.characterOffset(ofPage: textIndex(for: currentPage)) ?? 0
            context = newContext
            discardPreparedLayouts()

            guard let chapterId = currentChapterId else { return }

            // The old layout stays on screen while the new one is measured, so a change of font does
            // not blank the page.
            Task { await load(chapterId: chapterId, anchor: layout == nil ? pendingAnchor : .offset(offset)) }
        }

        private func discardPreparedLayouts() {
            layouts.removeAll()
            prefetch?.cancel()
            prefetch = nil
            pagination = nil
            paginating?.cancel()
            paginating = nil
            backgroundMeasuring?.cancel()
            backgroundMeasuring = nil
        }

        // MARK: - Opening the book

        /// The heading the reader sets over a chapter, where it sets one at all.
        ///
        /// A book off a file carries its own divisions, so a chapter it gave no name to is not a chapter
        /// the book made: numbering it puts "Chapter 1" over a page of front matter. The service counts
        /// its own chapters and an untitled one there still wants its number.
        private static func heading(at position: Int, title: String?, workId: Int) -> ChapterHeading {
            let named = !(title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

            guard named || !BookNumbering.isLocal(workId) else { return ChapterHeading() }

            return ChapterHeading.make(position: position, title: title)
        }

        func loadIfNeeded() async {
            guard !hasLoaded else { return }

            hasLoaded = true
            isLoading = true

            // Opening a book counts as seeing whatever the daily sweep flagged for it.
            await UpdateBadge.clear(workId: workId)

            await rereadIfBehind()

            book = await store.book(id: workId)?.summary
            chapters = await store.chapters(workId: workId)
            bookmarks = await store.bookmarks(workId: workId)
            let position = await store.position(workId: workId)

            if !chapters.isEmpty { openTarget(position: position) }

            await refreshContents()

            if currentChapterId == nil { openTarget(position: position) }

            // Behind the reading: a link names a place rather than a chapter, and which chapter holds
            // it is only known once every chapter has been looked at.
            Task { [weak self] in await self?.readPlaces() }

            isLoading = layout == nil && errorMessage == nil
            await refreshBook()

            // The rest of the book is prepared behind the reader, who is already on its first page.
            await processor.start(workId: workId, chapters: chapters)
        }

        /// Reads the book again from its kept file where an older build read it, before its chapters are
        /// taken out of the store.
        ///
        /// A chapter holds whatever the parser made of the file at the time, so a parser that has since
        /// learned something reaches a book only through the file. One book as it opens rather than a
        /// library at launch, which is what puts reading positions at risk; `BookInstaller` carries the
        /// position across whatever the new reading cuts the book into.
        private func rereadIfBehind() async {
            guard
                BookNumbering.isLocal(workId),
                LocalBookFiles.hasKeptFile(workId: workId),
                await store.localBook(workId: workId)?.isBehindThisBuild == true
            else {
                return
            }

            await inbox.reaccept(workId: workId)
        }

        /// Picks the chapter to open: the one asked for, else the one the reader stopped in, else the first.
        private func openTarget(position: ReadingPosition?) {
            let requested = requestedChapterId.flatMap { candidate in
                readableChapters.first { $0.id == candidate }?.id
            }
            let stored = position.flatMap { saved in
                readableChapters.first { $0.id == saved.chapterId }?.id
            }

            guard
                let target = requested ?? stored ?? readableChapters.first?.id
            else {
                errorMessage = String(localized: "This book has no chapters you can read yet.")
                isLoading = false
                return
            }

            // Resuming beats starting over whenever the chapter is the one the reader stopped in, even
            // when the book page asked for it by id.
            let anchor: PageAnchor = target == stored ? .offset(position?.characterOffset ?? 0) : .first

            open(chapterId: target, anchor: anchor)
            Task { await startSession(chapterId: target) }
        }

        /// True for a book that came from a file. Nothing about it is the service's to answer.
        private var isLocal: Bool { BookNumbering.isLocal(workId) }

        private func refreshContents() async {
            do {
                // A book from a file routes to a loader with nothing to give, which is the whole of
                // what used to be an isLocal branch here.
                guard let fetched = try await session.loaders.contents(of: workId) else { return }

                await store.store(chapters: fetched, workId: workId)
                chapters = fetched.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
                isOffline = false
            } catch {
                isOffline = true

                if chapters.isEmpty {
                    errorMessage = String(localized: "Couldn’t open this book.")
                    isLoading = false
                }
            }
        }

        /// The book itself, for the title page. Cached first, so it is there before the service answers.
        private func refreshBook() async {
            guard !isLocal, book == nil else { return }
            guard let details = try? await session.client.workDetails(id: workId) else { return }

            let summary = Book(details)
            book = summary
            await store.store(book: summary, tags: details.tags)
        }

        /// Asks the service where this reader stopped and keeps the session id for progress reports.
        private func startSession(chapterId: Int) async {
            guard !isLocal, session.isSignedIn else { return }
            guard
                let stats = try? await session.client.startReading(workId: workId, chapterId: chapterId)
            else {
                return
            }

            sessionId = stats.sessionId
        }

        // MARK: - Moving through the book

        /// Shows a chapter, without waiting when it has already been laid out.
        func open(chapterId: Int, anchor: PageAnchor = .first) {
            currentChapterId = chapterId
            lastReportedProgress = -1
            pendingAnchor = anchor
            errorMessage = nil

            if let prepared = layouts[chapterId] {
                guard sharesWithOneNotLaidOut(prepared) else { return install(prepared, anchor: anchor) }

                // Held only where half the page is missing. Everything already laid out installs at
                // once, which is what keeps a turn between chapters immediate.
                Task { [weak self] in
                    await self?.layOutWhoeverSharesAPage(with: prepared)

                    guard self?.currentChapterId == chapterId else { return }

                    self?.install(prepared, anchor: anchor)
                }

                return
            }

            layout = nil
            isLoading = true
            Task { await load(chapterId: chapterId, anchor: anchor) }
        }

        func goToNextChapter() {
            guard let beyond = beyondThisPage() else { return }

            open(chapterId: beyond.id, anchor: beyond.page == 0 ? .first : .page(beyond.page))
        }

        /// The next chapter with a page the reader has not been shown, and which of its pages that is.
        ///
        /// Where a chapter began on this chapter's last page, its first page is the one already being
        /// looked at, so the turn goes to its second. A chapter short enough to have ended on that page
        /// as well was read there whole and has no page to turn onto, so the reader is carried past it
        /// to the next that has one. Several in a row are all passed: a book's front matter often runs
        /// to a few lines apiece, and turning onto the page they shared would show it a second time.
        private func beyondThisPage() -> (id: Int, page: Int)? {
            guard var previous = layout, var index = currentIndex else { return nil }

            let chapters = readableChapters

            while index + 1 < chapters.count {
                let next = chapters[index + 1]

                guard let after = layouts[next.id] else { return (next.id, 0) }

                let shares = BookPagination.sharesLastPage(of: previous, with: after, context: previous.context)
                let target = shares ? 1 : 0

                if after.pageRanges.indices.contains(target) { return (next.id, target) }

                previous = after
                index += 1
            }

            return nil
        }

        func goToPreviousChapter() {
            guard let before = beforeThisPage() else { return }

            open(chapterId: before.id, anchor: .page(before.page))
        }

        /// The chapter behind this page with a page the reader has not been shown, and which page.
        ///
        /// The mirror of ``beyondThisPage()``. Where this chapter began on the one before's last page,
        /// that page is the one being looked at and the turn goes to the one before it. A chapter with
        /// nothing else to show was read whole on the page it shared, and the reader is carried back
        /// past it.
        private func beforeThisPage() -> (id: Int, page: Int)? {
            guard var current = layout, var index = currentIndex else { return nil }

            let chapters = readableChapters

            while index > 0 {
                let previous = chapters[index - 1]

                guard let before = layouts[previous.id] else { return (previous.id, 0) }

                let shares = BookPagination.sharesLastPage(of: before, with: current, context: before.context)
                let target = before.pageCount - 1 - (shares ? 1 : 0)

                if target >= 0, before.pageRanges.indices.contains(target) { return (previous.id, target) }

                current = before
                index -= 1
            }

            return nil
        }

        private func load(chapterId: Int, anchor: PageAnchor) async {
            await measureBook(through: chapterId)

            guard
                let content = await content(for: chapterId)
            else {
                guard currentChapterId == chapterId else { return }

                errorMessage = String(localized: "Couldn’t load this chapter.")
                isLoading = false
                return
            }
            guard currentChapterId == chapterId, let context else { return }

            let built = await makeLayout(
                chapterId: chapterId,
                content: content,
                context: context,
                startOffset: pagination?.placement(of: chapterId)?.startOffset ?? 0,
                reportsProgress: true
            )
            paginationProgress = nil

            guard let built else { return }

            await layOutWhoeverSharesAPage(with: built)
            install(built, anchor: anchor)
            measureTheRest()
        }

        /// Lays out a neighbour that shares a page with this chapter, before the page is shown.
        ///
        /// A chapter running on into another's last page is part of that page rather than something to
        /// read ahead for. Left to the prefetch, the page draws once without it and again when it
        /// lands, so the missing half appears after the turn has settled.
        ///
        /// Only a neighbour that actually shares: one starting a page of its own is read ahead for as
        /// before, and costs the reader nothing here.
        /// True where a chapter shares a page with a neighbour that has not been laid out, so drawing
        /// it now would leave that half of the page blank until the neighbour arrives.
        private func sharesWithOneNotLaidOut(_ built: ChapterLayout) -> Bool {
            if built.startOffset > 0, let previous = previousChapter, layouts[previous.id] == nil {
                return true
            }

            guard let next = nextChapter, layouts[next.id] == nil else { return false }

            return (pagination?.placement(of: next.id)?.startOffset ?? 0) > 0
        }

        private func layOutWhoeverSharesAPage(with built: ChapterLayout) async {
            // The chapter being installed rather than the one still on screen: this runs before it is
            // installed, so the reader's own layout is still the last one.
            if built.startOffset > 0, let previous = previousChapter, layouts[previous.id] == nil {
                await prepare(chapterId: previous.id)
            }

            guard
                let next = nextChapter,
                layouts[next.id] == nil,
                (pagination?.placement(of: next.id)?.startOffset ?? 0) > 0
            else { return }

            await prepare(chapterId: next.id)
        }

        /// Measures as much of the book as it takes to put the reader on a page, and no more.
        ///
        /// Every chapter's place comes from one pass in order, so a chapter opened from the contents
        /// sits exactly where it will sit when the reader later reads into it from the chapter before.
        /// Working each chapter out as it was reached was what moved the text under the reader.
        ///
        /// A chapter's place depends on every chapter before it and on none of the ones after, so the
        /// run ending at the one being opened is enough to start reading. The chapter after it is
        /// measured too, since whether it begins on this chapter's last page has to be settled before
        /// the reader can turn onto that page.
        private func measureBook(through chapterId: Int) async {
            guard let context, !readableChapters.isEmpty else { return }

            if pagination == nil { pagination = BookPagination.make(workId: workId, context: context) }

            let chapters = readableChapters
            let index = chapters.firstIndex { $0.id == chapterId } ?? 0
            let needed = min(index + 2, chapters.count)

            guard let pagination, pagination.measured < needed else { return }

            if let running = paginating { return await running.value }

            let task = Task { [weak self] in
                await pagination.measure(
                    chapters: chapters,
                    through: needed,
                    content: { [weak self] in await self?.storedContent(for: $0) },
                    onProgress: { [weak self] value in self?.paginationProgress = value }
                )
                self?.paginationProgress = nil
                // The book grew a measured chapter, so where its pages fall has moved.
                self?.refreshBookPaging()
            }

            paginating = task
            await task.value
            paginating = nil
        }

        /// Measures what is left of the book behind the reader, who is already reading it.
        ///
        /// One chapter at a time at utility priority, and never while a page is turning. Laying a
        /// chapter out runs on the main actor, so a chapter measured mid-turn takes its frames from the
        /// animation, and the turn is the one thing in the reader that has to stay smooth.
        private func measureTheRest() {
            guard
                backgroundMeasuring == nil,
                let pagination,
                let context,
                !pagination.hasMeasuredEverything(of: readableChapters)
            else { return }

            let chapters = readableChapters

            backgroundMeasuring = Task(priority: .utility) { [weak self] in
                while !pagination.hasMeasuredEverything(of: chapters) {
                    guard !Task.isCancelled, let self, context == self.context else { break }

                    await self.waitOutTheTurn()
                    await pagination.measure(
                        chapters: chapters,
                        through: pagination.measured + 1,
                        content: { [weak self] in await self?.storedContent(for: $0) }
                    )
                    // Each chapter measured turns a guess at the book's length into pages.
                    self.refreshBookPaging()
                }

                self?.backgroundMeasuring = nil
            }
        }

        /// Stands the background pass off while a page is turning, and for a moment afterwards so a
        /// reader turning steadily is never measured against.
        private func waitOutTheTurn() async {
            while Date.now < quietUntil {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        /// Called as a turn begins. Nothing heavy runs until the animation has had the main actor to
        /// itself and the reader has had a moment to start another turn.
        func noteTurn() { quietUntil = .now.addingTimeInterval(Self.quietAfterTurn) }

        private static let quietAfterTurn: TimeInterval = 0.6

        private func install(_ built: ChapterLayout, anchor: PageAnchor) {
            layouts[built.chapterId] = built
            layout = built
            currentChapterId = built.chapterId

            rememberWords(in: built)

            switch anchor {
                case .first:
                    currentPage = 0
                case let .page(page):
                    currentPage = min(max(0, page + titlePageCount), max(0, pageCount - 1))
                case let .offset(offset):
                    currentPage =
                        offset < 0
                        ? 0
                        : built.pageIndex(containing: offset) + titlePageCount
            }

            isLoading = false
            errorMessage = nil
            savePosition(now: built.chapterId != wroteChapterId)
            wroteChapterId = built.chapterId
            reportProgress()
            prefetchNeighbours()
        }

        // MARK: - Reading ahead

        /// Lays out the chapters either side of this one while the reader is busy with this one, so a
        /// chapter break costs a page turn rather than a round trip.
        ///
        /// Forwards, they are laid out in order: where a chapter has room left on its last page, the one
        /// after it starts there rather than on a page of its own, which means each layout depends on
        /// the one before it.
        private func prefetchNeighbours() {
            guard let index = currentIndex else { return }

            trimCaches(around: index)
            prefetch?.cancel()
            prefetch = Task { [weak self] in
                await self?.prepareAhead(from: index)
                await self?.prepareBehind(from: index)
            }
        }

        /// Lays out the neighbours where the book pass said they go, so nothing is measured twice and
        /// nothing shifts once it has been drawn.
        private func prepareAhead(from index: Int) async {
            let chapters = readableChapters

            for position in (index + 1) ..< min(index + 3, chapters.count) {
                guard !Task.isCancelled else { return }
                guard layouts[chapters[position].id] == nil else { continue }

                _ = await prepare(chapterId: chapters[position].id)
            }
        }

        private func prepareBehind(from index: Int) async {
            guard index > 0 else { return }

            let id = readableChapters[index - 1].id

            guard layouts[id] == nil, !Task.isCancelled else { return }

            _ = await prepare(chapterId: id)
        }

        /// Lays a neighbour out, but only once the book pass has said where it goes.
        ///
        /// Reading ahead of the pass is reading ahead of the answer: the chapter would be set as if it
        /// started a page of its own, and then drawn over the page it turns out to share. It is laid out
        /// at the next chapter break instead, by when the pass has passed it.
        @discardableResult
        private func prepare(chapterId: Int) async -> ChapterLayout? {
            guard let context, let placement = pagination?.placement(of: chapterId) else { return nil }
            guard let content = await content(for: chapterId) else { return nil }
            guard
                let built = await makeLayout(
                    chapterId: chapterId,
                    content: content,
                    context: context,
                    startOffset: placement.startOffset,
                    reportsProgress: false
                )
            else { return nil }

            layouts[chapterId] = built
            return built
        }

        /// Keeps the laid-out chapters to the ones around the reader; a book has too many to hold them all.
        private func trimCaches(around index: Int) {
            let keep = Set(readableChapters[max(0, index - 1) ..< min(index + 3, readableChapters.count)].map(\.id))
            layouts = layouts.filter { keep.contains($0.key) || $0.key == currentChapterId }
            parsed = parsed.filter { keep.contains($0.key) || $0.key == currentChapterId }
        }

        private func makeLayout(
            chapterId: Int,
            content: ChapterContent,
            context: ChapterLayout.Context,
            startOffset: CGFloat,
            reportsProgress: Bool
        ) async -> ChapterLayout? {
            let position = (readableChapters.firstIndex { $0.id == chapterId } ?? 0) + 1
            let title = readableChapters.first { $0.id == chapterId }?.title
            let report: (@MainActor (Double) -> Void)? = { [weak self] value in
                self?.paginationProgress = value
            }
            let built = await ChapterLayout.make(
                chapterId: chapterId,
                content: content,
                heading: Self.heading(at: position, title: title, workId: workId),
                context: context,
                startOffset: startOffset,
                columns: store,
                onProgress: reportsProgress ? report : nil
            )

            // The style may have moved on while this was being measured.
            guard context == self.context else { return nil }

            return built
        }

        /// Text for the measuring pass: whatever is already here, parsed but not kept.
        ///
        /// It walks every chapter, so it neither asks the service for one nor holds on to what it
        /// parses: the cache is for the handful of chapters around the reader.
        private func storedContent(for chapterId: Int) async -> ChapterContent? {
            if let cached = parsed[chapterId] { return cached }

            return await processor.content(workId: workId, chapterId: chapterId)
        }

        /// The chapter's text: prepared already, else stored on the device, else from the service.
        private func content(for chapterId: Int) async -> ChapterContent? {
            if let cached = parsed[chapterId] { return cached }

            if let prepared = await processor.content(workId: workId, chapterId: chapterId) {
                parsed[chapterId] = prepared
                return prepared
            }

            do {
                // A book from a file carries all its text already, and its loader says so by
                // answering nothing.
                guard let chapter = try await session.loaders.body(of: chapterId, in: workId) else { return nil }

                await store.store(body: chapter, workId: workId)
                let prepared = await processor.content(workId: workId, chapterId: chapterId)
                parsed[chapterId] = prepared
                isOffline = false
                return prepared
            } catch {
                isOffline = true
                return nil
            }
        }

        // MARK: - Progress

        /// Keeps the device's own copy of the reading position, which is the only one that works: the
        /// service accepts the position and stores nothing. See `Documentation/API.md`.
        /// - Parameter now: true to write without waiting, for a move the wait would lose. Leaving a
        ///   chapter is one: the mark jumps by a whole chapter, and the reader may be gone before the
        ///   wait is out.
        private func savePosition(now: Bool = false) {
            guard layout != nil, let chapterId = currentChapterId else { return }

            let offset = storedOffset
            let overall = bookProgress
            positionSaver?.cancel()
            positionSaver = Task { [store, workId] in
                if !now {
                    try? await Task.sleep(for: .milliseconds(400))

                    guard !Task.isCancelled else { return }
                }

                await store.store(position: .init(
                    workId: workId,
                    chapterId: chapterId,
                    characterOffset: offset,
                    updatedAt: .now
                ))
                await store.store(progress: overall, workId: workId)
            }
        }

        /// Writes the position at once and tells the service where the reader stopped, whatever the
        /// last coarse step reported.
        ///
        /// The ordinary save waits 400ms so a run of page turns writes once, and a suspended app never
        /// runs that task. Leaving the reader, and the app leaving the screen, are the two moments the
        /// wait has to be given up.
        func flushPosition() {
            positionSaver?.cancel()

            guard layout != nil, let chapterId = currentChapterId else { return }

            let offset = storedOffset
            let overall = bookProgress

            Task { [store, workId] in
                await store.store(position: .init(
                    workId: workId,
                    chapterId: chapterId,
                    characterOffset: offset,
                    updatedAt: .now
                ))
                await store.store(progress: overall, workId: workId)
                // The shelf draws the mark on a cover from the store, and the zoom takes its picture of
                // that cover as the book starts closing. Told afterwards, it animates the old mark home
                // and corrects it once the book has landed.
                BookInbox.shared.libraryChanged()
            }

            reportProgress(force: true)
        }

        /// Syncs the position upstream in coarse steps rather than on every page.
        private func reportProgress(force: Bool = false) {
            guard pageCount > 0, session.isSignedIn, let chapterId = currentChapterId else { return }

            let chapterProgress = Double(currentPage + 1) / Double(pageCount)

            guard force || chapterProgress - lastReportedProgress >= 0.05 || chapterProgress >= 0.999 else { return }

            lastReportedProgress = chapterProgress
            let overall = overallProgress(chapterProgress: chapterProgress)

            Task { [session, workId, sessionId] in
                await session.loaders.report(
                    ReadingPosition(workId: workId, chapterId: chapterId, characterOffset: 0, updatedAt: .now),
                    chapterProgress: chapterProgress,
                    bookProgress: overall,
                    sessionId: sessionId
                )
            }
        }

        /// How far into the whole book this page sits. The library draws its ring from this, since the
        /// service keeps no progress of its own.
        private var bookProgress: Double {
            guard pageCount > 0 else { return 0 }

            return overallProgress(chapterProgress: Double(currentPage + 1) / Double(pageCount))
        }

        /// Weighs the finished chapters by their length so the book-level figure tracks characters read.
        private func overallProgress(chapterProgress: Double) -> Double {
            let readable = readableChapters
            let total = readable.reduce(0) { $0 + ($1.textLength ?? 0) }

            guard total > 0, let index = currentIndex else { return chapterProgress }

            let before = readable.prefix(index).reduce(0) { $0 + ($1.textLength ?? 0) }
            let current = Double(readable[index].textLength ?? 0) * chapterProgress
            return min(1, max(0, (Double(before) + current) / Double(total)))
        }
    }
}
