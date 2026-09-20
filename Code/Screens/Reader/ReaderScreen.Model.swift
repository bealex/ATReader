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
        /// Where to land in a chapter.
        enum PageAnchor: Equatable {
            /// The chapter's opening: the book's title page, for the first chapter.
            case first
            /// The character the reader stopped on, which survives a change of font.
            case offset(Int)
            /// A passage found by searching, and roughly where it stood. The words say which passage it
            /// is; the offset only tells two alike apart.
            case passage(String, near: Int)
        }

        /// What one turn moves: a page, or two standing side by side.
        struct Sheet: Equatable {
            let pages: [BookPage]

            var start: BookPosition { pages[0].start }
            var end: BookPosition { pages[pages.count - 1].end }

            /// Whether the book's title stands over the sheet. Every sheet of text takes it, except one
            /// carrying the title page, which already says what the book is called.
            var showsTitle: Bool { pages.contains(where: \.isText) && !pages.contains(where: \.isTitle) }
        }

        let workId: Int
        let workTitle: String

        private(set) var book: Book?
        private(set) var chapters: [BookChapter] = []
        private(set) var currentChapterId: Int?
        private(set) var isLoading = false
        private(set) var errorMessage: String?

        /// True when the last request to the service failed and the reader is running off the device.
        private(set) var isOffline = false

        /// The stretches of this book the reader marked.
        private(set) var bookmarks: [Bookmark] = []

        /// What the page calls the book: its own name, with whatever its series writes into every one of
        /// its titles taken off. The same name the shelf gives it, and the title page names the series
        /// under it anyway.
        var bookTitle: String {
            guard let book else { return workTitle }

            return SeriesNumbering.title(book.title, in: book.seriesTitle, volume: book.seriesOrder)
        }

        /// The sheets the reader has been shown since the page last changed shape, the one on screen
        /// among them. A turn back and forth shows the same pages, and a page further off is cut again.
        private(set) var sheets: [Sheet] = []
        private(set) var sheetIndex = 0

        /// True from a turn onto a sheet not yet cut until it has been, which the reader sees as a blank
        /// page for the moment it takes.
        private(set) var isWaitingForSheet = false

        /// How many pages the book runs to at this setting, worked out from its length.
        private(set) var bookPages: Int?

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

        /// The book cut into pages for the style and size now in force.
        @ObservationIgnored
        private var bookLayout: BookLayout?

        /// The chapters the layout was made from, so a list read again unchanged does not throw it away.
        @ObservationIgnored
        private var laidChapters: [BookLayout.Chapter] = []

        /// Where to open once there is a layout to open in.
        @ObservationIgnored
        private var pendingPosition: BookPosition?

        /// Counts every time the pages are thrown away, so work begun for the old ones is dropped.
        @ObservationIgnored
        private var generation = 0

        @ObservationIgnored
        private var showing: Task<Void, Never>?

        @ObservationIgnored
        private var fillingForward: Task<Void, Never>?

        @ObservationIgnored
        private var fillingBackward: Task<Void, Never>?

        @ObservationIgnored
        private var parsed: [Int: ChapterContent] = [:]

        @ObservationIgnored
        private var sessionId: String?

        @ObservationIgnored
        private var requestedChapterId: Int?

        @ObservationIgnored
        private var hasLoaded = false

        @ObservationIgnored
        private var lastReportedProgress: Double = -1

        /// The chapter the last position was written against, so a move to another one is written
        /// through rather than waited on.
        @ObservationIgnored
        private var wroteChapterId: Int?

        @ObservationIgnored
        private var positionSaver: Task<Void, Never>?

        /// The chapters whose marks have been given their words, for the layout now in force.
        @ObservationIgnored
        private var rememberedChapters: Set<Int> = []

        /// The chapters whose marks have been given the page they stand on.
        @ObservationIgnored
        private var pagedChapters: Set<Int> = []

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

        var chapterTitle: String? {
            readableChapters.first { $0.id == currentChapterId }?.displayTitle
        }

        /// How many pages stand side by side on one sheet. Told by the view, which is the only thing
        /// that knows how much room the window has, and never below one.
        private(set) var columns = 1

        /// The sheet in front of the reader.
        var currentSheet: Sheet? {
            guard !isWaitingForSheet, sheets.indices.contains(sheetIndex) else { return nil }

            return sheets[sheetIndex]
        }

        /// The sheet a turn away, where it has been cut: `-1` behind the reader, `1` ahead.
        func sheet(at step: Int) -> Sheet? {
            guard step != 0 else { return currentSheet }
            guard !isWaitingForSheet, sheets.indices.contains(sheetIndex + step) else { return nil }

            return sheets[sheetIndex + step]
        }

        /// The pages in front of the reader: one, or a spread of two.
        var pagesOnScreen: [BookPage] { currentSheet?.pages ?? [] }

        /// Which page stands in one column of the sheet the reader is on.
        func page(inColumn column: Int) -> BookPage? {
            let pages = pagesOnScreen

            return pages.indices.contains(column) ? pages[column] : nil
        }

        /// True where a turn forward has somewhere to go: a sheet already cut, or more of the book.
        var canTurnForward: Bool {
            guard let sheet = currentSheet, let last = sheet.pages.last else { return false }
            guard !sheets.indices.contains(sheetIndex + 1) else { return true }

            return bookLayout.map { !$0.isLast(last) } ?? false
        }

        /// True where a turn back has somewhere to go. Only the title page has nothing before it.
        var canTurnBack: Bool {
            guard let sheet = currentSheet else { return false }

            return sheetIndex > 0 || !sheet.pages[0].isTitle
        }

        /// Where the reader is, as a position to keep: where the sheet in front of them begins.
        private var storedPosition: BookPosition? { currentSheet?.start }

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
            pagesOnScreen.first?.pieces.flatMap { $0.layout.typesetLines(on: $0.page) } ?? []
        }

        /// The text the page is showing, for a debug report.
        var pageText: String {
            guard let page = pagesOnScreen.first else { return "" }

            return page.isTitle ? workTitle : page.pieces.map { $0.layout.pageText($0.page) }.joined(separator: "\n")
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
            let pageId: String
            let chapterId: Int
            /// The stretch it covers, counted the way a mark and a reading position are.
            let source: Range<Int>

            var id: String { "\(selection.range.location).\(selection.range.length)" }
        }

        private(set) var picked: PickedText?

        /// Folding a chapter costs a pass over all of it, and every redraw asks where its marks stand.
        @ObservationIgnored
        private var foldedChapters: [Int: BookSearch.Folded] = [:]

        /// Picks out everything between two points on one page, out to whole words.
        func pickOut(from start: CGPoint, to finish: CGPoint, on page: BookPage) {
            for piece in page.pieces {
                guard let range = piece.layout.words(from: start, to: finish, on: piece.page) else { continue }

                let chosen = piece.layout.selection(of: range)

                guard !chosen.isEmpty else { continue }

                picked = PickedText(
                    selection: chosen,
                    rects: piece.layout.rects(of: range, on: piece.page),
                    pageId: page.id,
                    chapterId: piece.layout.chapterId,
                    source: piece.layout.position(ofLaidOut: range.location)
                        ..< piece.layout.position(ofLaidOut: NSMaxRange(range))
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
            pagesOnScreen.flatMap { page in
                page.pieces.map { piece in
                    let start = piece.layout.startOffset(of: piece.page)
                    let end = piece.layout.endOffset(of: piece.page)

                    return Shown(chapterId: piece.layout.chapterId, start: start, end: max(end, start + 1))
                }
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
        func folded(_ chapterId: Int) -> BookSearch.Folded? {
            if let held = foldedChapters[chapterId] { return held }

            guard let built = bookLayout?.loadedLayout(of: chapterId) else { return nil }

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
        ///
        /// One mark, where the sheet begins, however many chapters it shows: a page carrying the end of
        /// one chapter and the start of another is one page to whoever marked it, and reopening at its
        /// first character brings all of it back.
        func toggleBookmark() {
            let already = bookmarksOnPage

            guard already.isEmpty else { return remove(already) }
            guard let shown = displayedRanges.first else { return }

            let standingOn = standing(at: shown.start, inChapter: shown.chapterId)
            let bare = Bookmark(
                workId: workId,
                chapterId: shown.chapterId,
                startOffset: shown.start,
                endOffset: shown.end,
                pageStart: standingOn?.start,
                lineOnPage: standingOn?.line,
                createdAt: .now
            )
            let made =
                bookLayout?.loadedLayout(of: shown.chapterId)
                .flatMap { words(for: bare, in: $0, of: BookSearch.fold($0.sourceText)) } ?? bare

            bookmarks.append(made)

            Task { [store] in await store.store(bookmark: made) }
        }

        /// Marks the words the reader picked out, at the line they start on.
        ///
        /// A mark already standing exactly there is left alone: two marks of one book never share a
        /// place, which is what lets one be found and taken away again.
        func bookmarkPicked() {
            guard let chosen = picked, let built = bookLayout?.loadedLayout(of: chosen.chapterId) else { return }

            let standingOn = standing(at: chosen.source.lowerBound, inChapter: chosen.chapterId)
            let bare = Bookmark(
                workId: workId,
                chapterId: chosen.chapterId,
                startOffset: chosen.source.lowerBound,
                endOffset: chosen.source.upperBound,
                pageStart: standingOn?.start,
                lineOnPage: standingOn?.line,
                createdAt: .now
            )

            guard !bookmarks.contains(where: { $0.id == bare.id }) else { return }

            let made = words(for: bare, in: built, of: BookSearch.fold(built.sourceText)) ?? bare

            bookmarks.append(made)

            Task { [store] in await store.store(bookmark: made) }
        }

        /// Where the page in front of the reader begins, and which of its lines a place falls on.
        ///
        /// What a mark keeps of the page it was made on, so reopening it sets that page again instead of
        /// cutting a fresh one whose first line is the marked one.
        private func standing(at offset: Int, inChapter chapterId: Int) -> (start: Int, line: Int)? {
            for page in pagesOnScreen {
                for piece in page.pieces where piece.layout.chapterId == chapterId {
                    let start = piece.layout.startOffset(of: piece.page)
                    let end = max(piece.layout.endOffset(of: piece.page), start + 1)

                    guard offset >= start, offset < end else { continue }

                    let at =
                        piece.layout.line(atPosition: offset, on: piece.page)?.index
                        ?? piece.page.lines.lowerBound

                    return (start, at - piece.page.lines.lowerBound)
                }
            }

            return nil
        }

        /// Where to open the book to put a mark back on the page it was made on.
        func opening(of mark: Bookmark) -> Int { mark.opening(at: place(of: mark)) }

        /// A mark as it stands on a page: where its line is, and how deep that line runs.
        struct StandingMark: Identifiable {
            let id: String
            let top: CGFloat
            let height: CGFloat
        }

        /// Every mark the page carries, against the line each one begins on.
        ///
        /// A mark covering a whole page hangs against its first line, which is where the reader made it.
        func marks(on page: BookPage) -> [StandingMark] {
            page.pieces.flatMap { piece in
                let start = piece.layout.startOffset(of: piece.page)
                let end = max(piece.layout.endOffset(of: piece.page), start + 1)

                return bookmarks(inChapter: piece.layout.chapterId).compactMap { mark -> StandingMark? in
                    let place = place(of: mark)
                    let stands = place.lowerBound < end && max(place.upperBound, place.lowerBound + 1) > start

                    guard
                        let line = stands
                            ? piece.layout.line(atPosition: max(place.lowerBound, start), on: piece.page)
                            : remembered(mark, on: piece, openingAt: start)
                    else { return nil }

                    return StandingMark(id: mark.id, top: line.edge, height: line.height)
                }
            }
        }

        /// The line a mark remembers standing on, where the page it opens is the page it was made on.
        ///
        /// A book read again moves the offsets under a mark whose words have gone, and the line it wrote
        /// down is then all that is left of where it stood.
        private func remembered(
            _ mark: Bookmark,
            on piece: BookPage.Piece,
            openingAt start: Int
        ) -> ChapterLayout.PlacedLine? {
            guard mark.pageStart == start, let index = mark.lineOnPage else { return nil }

            let wanted = piece.page.lines.lowerBound + index

            guard piece.page.lines.contains(wanted) else { return nil }

            return piece.layout.placedLines(on: piece.page).first { $0.index == wanted }
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
            guard rememberedChapters.insert(built.chapterId).inserted else { return }

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

        /// Gives every mark written before marks kept a page the page it stands on.
        ///
        /// Each chapter holding one is cut from its own beginning, that being the only way to learn
        /// which page holds a place. Run once a book, behind the page the reader is on, and against the
        /// size and face in force: a mark keeps the page it was made on, and this is the nearest thing
        /// to it left.
        private func rememberPages() {
            let waiting = Set(bookmarks.filter { $0.pageStart == nil }.map(\.chapterId))
                .subtracting(pagedChapters)

            guard !waiting.isEmpty, let bookLayout else { return }

            pagedChapters.formUnion(waiting)

            Task(priority: .utility) { [weak self] in
                for chapterId in waiting.sorted() {
                    guard let self else { return }

                    await self.rememberPages(inChapter: chapterId, of: bookLayout)
                }
            }
        }

        private func rememberPages(inChapter chapterId: Int, of layout: BookLayout) async {
            let standing = bookmarks.filter { $0.chapterId == chapterId && $0.pageStart == nil }

            guard !standing.isEmpty else { return }

            let wanted = Dictionary(standing.map { (place(of: $0).lowerBound, $0) }) { first, _ in first }
            let places = await layout.pagePlaces(of: Array(wanted.keys), in: chapterId)
            let written = places.compactMap { at, place in wanted[at].map { paged($0, on: place) } }

            for mark in written {
                guard let at = bookmarks.firstIndex(where: { $0.id == mark.id }) else { continue }

                bookmarks[at] = mark
            }

            for mark in written { await store.store(bookmark: mark) }
        }

        /// The same mark, carrying the page it was found to stand on.
        private func paged(_ mark: Bookmark, on place: BookLayout.PagePlace) -> Bookmark {
            Bookmark(
                workId: mark.workId,
                chapterId: mark.chapterId,
                startOffset: mark.startOffset,
                endOffset: mark.endOffset,
                text: mark.text,
                occurrence: mark.occurrence,
                pageStart: place.start,
                lineOnPage: place.line,
                createdAt: mark.createdAt
            )
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
                pageStart: mark.pageStart,
                lineOnPage: mark.lineOnPage,
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
            bookLayout?.loadedLayout(of: id)?.sourceLength ?? chapters.first { $0.id == id }?.textLength
        }

        // MARK: - Finding a passage in the book

        /// What the reader is looking for, and every place the book says it.
        private(set) var findQuery = ""
        private(set) var found: [Found] = []
        /// Which of them the reader has been taken to.
        private(set) var foundAt: Int?
        /// True while the rest of the book is still being looked through.
        private(set) var isFinding = false

        /// The words the reader stands on, and which chapter they stand in.
        struct FoundPlace: Equatable {
            let chapterId: Int
            /// The stretch they cover, counted the way a reading position is.
            let range: Range<Int>
        }

        /// Where the place the reader was taken to stands, worked out as they were taken there rather
        /// than on every redraw: finding it costs a pass over the chapter, and a turn redraws each frame.
        private(set) var foundPlace: FoundPlace?

        @ObservationIgnored
        private var finding: Task<Void, Never>?

        /// Looks for a passage through the whole book, and takes the reader to the first one they have
        /// not already read past.
        func find(_ words: String) {
            let wanted = words.trimmingCharacters(in: .whitespacesAndNewlines)

            finding?.cancel()
            findQuery = wanted
            found = []
            foundAt = nil
            foundPlace = nil
            isFinding = false

            guard !BookSearch.fold(wanted).isEmpty else { return }

            isFinding = true
            finding = Task { [weak self] in await self?.walk(for: wanted) }
        }

        /// Puts the search away, and everything it found with it.
        func stopFinding() {
            finding?.cancel()
            finding = nil
            findQuery = ""
            found = []
            foundAt = nil
            foundPlace = nil
            isFinding = false
        }

        func showNextFound() {
            guard !found.isEmpty else { return }

            show(found: ((foundAt ?? -1) + 1) % found.count)
        }

        func showPreviousFound() {
            guard !found.isEmpty else { return }

            show(found: ((foundAt ?? 0) + found.count - 1) % found.count)
        }

        /// Takes the reader to one of the places found.
        func show(found index: Int) {
            guard found.indices.contains(index) else { return }

            foundAt = index
            let hit = found[index]

            open(chapterId: hit.chapterId, anchor: .passage(findQuery, near: hit.offset))
        }

        /// Looks through the book a chapter at a time, telling the reader what it has as it goes.
        ///
        /// Chapter by chapter rather than all at once: a book whose later chapters are not on the device
        /// has to fetch them, and a reader watching the count climb can use what is already found.
        private func walk(for words: String) async {
            var hits: [Found] = []

            for chapter in readableChapters {
                guard !Task.isCancelled else { return }

                if let text = await findableText(of: chapter.id) {
                    hits += BookSearch.matches(of: words, in: text)
                        .map { Found(chapterId: chapter.id, offset: $0.lowerBound) }
                }

                guard !Task.isCancelled else { return }

                found = hits

                if foundAt == nil, let next = hits.firstIndex(where: isPastTheReader) { show(found: next) }

                await Task.yield()
            }

            isFinding = false

            // Nothing ahead of them, so the book is taken from the top rather than left saying it found
            // something and showing none of it.
            if foundAt == nil, !found.isEmpty { show(found: 0) }
        }

        /// True where a place found stands at or beyond the page the reader is on.
        private func isPastTheReader(_ hit: Found) -> Bool {
            guard
                let here = currentIndex,
                let there = readableChapters.firstIndex(where: { $0.id == hit.chapterId })
            else { return true }

            return there > here || (there == here && hit.offset >= (storedPosition?.offset ?? 0))
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

            wayBack = storedPosition.map { Place(chapterId: $0.chapterId, offset: $0.offset) }
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
        func link(at point: CGPoint, on page: BookPage) -> String? {
            for piece in page.pieces {
                if let found = piece.layout.link(at: point, on: piece.page) { return found.target }
            }

            return nil
        }

        func note(at point: CGPoint, on page: BookPage) -> TappedNote? {
            for piece in page.pieces {
                guard
                    let marker = piece.layout.note(at: point, on: piece.page),
                    let note = parsed[piece.layout.chapterId]?.notes[marker.id]
                else { continue }

                return TappedNote(note: note, rect: marker.rect)
            }

            return nil
        }

        /// Every note the page showing refers to, for a reader who cannot touch a marker they can't see.
        var notesOnPage: [BookNote] {
            pagesOnScreen.flatMap { page in
                page.pieces.flatMap { piece in
                    piece.layout.notes(on: piece.page).compactMap { parsed[piece.layout.chapterId]?.notes[$0] }
                }
            }
        }

        // MARK: - How far into the book

        /// How far into the book a place stands, each chapter weighed by how long it is.
        func progress(at position: BookPosition) -> Double {
            let readable = readableChapters

            guard let index = readable.firstIndex(where: { $0.id == position.chapterId }) else { return 0 }

            let within = share(of: position)
            let total = readable.reduce(0) { $0 + ($1.textLength ?? 0) }

            guard total > 0 else { return (Double(index) + within) / Double(readable.count) }

            let before = readable.prefix(index).reduce(0) { $0 + ($1.textLength ?? 0) }
            let current = Double(readable[index].textLength ?? 0) * within

            return min(1, max(0, (Double(before) + current) / Double(total)))
        }

        /// Which page of the book a place stands on, at the length the book comes to now. Nothing where
        /// the book's own length isn't known, since there are no pages to count.
        func pageNumber(at position: BookPosition) -> Int? {
            guard let bookPages, bookPages > 0 else { return nil }

            return max(1, Int((Double(bookPages) * progress(at: position)).rounded()))
        }

        /// How far into its own chapter a place stands, `0…1`.
        private func share(of position: BookPosition) -> Double {
            guard position.offset > 0 else { return 0 }

            let length =
                bookLayout?.loadedLayout(of: position.chapterId)?.sourceLength
                ?? chapters.first { $0.id == position.chapterId }?.textLength
                ?? 0

            return length > 0 ? min(1, Double(position.offset) / Double(length)) : 0
        }

        /// Works out how many pages the book comes to at the setting in force, from its length alone.
        private func countBookPages() {
            let chapterLength = readableChapters.reduce(0) { $0 + ($1.textLength ?? 0) }
            let characters = chapterLength > 0 ? chapterLength : (book?.textLength ?? 0)

            guard let context, characters > 0 else { return bookPages = nil }

            bookPages = BookLength.pages(characters: characters, context: context, language: chapterLanguage)
        }

        // MARK: - Layout

        /// Adopts a new page size or reading style, keeping the reader's place.
        ///
        /// Takes the shape of the page and how many of them stand on a sheet, which always move together:
        /// a spread that gained or lost a page is a page of a different width.
        func apply(context newContext: ChapterLayout.Context, columns pages: Int) {
            guard newContext.isUsable else { return }

            let reshaped = max(1, pages) != columns

            columns = max(1, pages)

            guard newContext != context || reshaped else { return }

            context = newContext
            countBookPages()

            if bookLayout?.context != newContext {
                rebuildLayout()
            } else if let position = storedPosition ?? pendingPosition {
                show(position)
            }
        }

        /// Makes the book's layout afresh for the chapters and setting in force, and puts the reader back
        /// where they were in it.
        private func rebuildLayout() {
            guard let context else { return }

            let laid = readableChapters.enumerated().map { place, chapter in
                BookLayout.Chapter(
                    id: chapter.id,
                    heading: Self.heading(at: place + 1, title: chapter.title, workId: workId),
                    opensItsOwnPage: max(1, chapter.level ?? 1) <= 1
                )
            }

            guard !laid.isEmpty else { return }
            guard bookLayout?.context != context || laid != laidChapters else { return }

            let anchor = storedPosition ?? pendingPosition

            laidChapters = laid
            rememberedChapters = []
            bookLayout = BookLayout(chapters: laid, context: context) { [weak self] id in
                await self?.content(for: id)
            }

            if let anchor { show(anchor) }
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

            rebuildLayout()
            countBookPages()

            if !chapters.isEmpty { openTarget(position: position) }

            await refreshContents()
            rebuildLayout()

            if currentChapterId == nil { openTarget(position: position) }

            // Behind the reading: a link names a place rather than a chapter, and which chapter holds
            // it is only known once every chapter has been looked at.
            Task { [weak self] in await self?.readPlaces() }

            isLoading = currentSheet == nil && errorMessage == nil
            await refreshBook()
            countBookPages()

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

        /// Shows a chapter, at its opening or at a place in it.
        func open(chapterId: Int, anchor: PageAnchor = .first) {
            lastReportedProgress = -1
            errorMessage = nil

            switch anchor {
                case .first:
                    let isFirst = readableChapters.first?.id == chapterId

                    show(BookPosition(chapterId: chapterId, offset: isFirst ? BookPosition.titleOffset : 0))
                case let .offset(offset):
                    show(BookPosition(chapterId: chapterId, offset: offset))
                case let .passage(words, near):
                    show(passage: words, near: near, in: chapterId)
            }
        }

        /// Lays the pages out afresh at a position: for a book just opened, a page that changed shape, or a
        /// jump to somewhere else in the book. What is on screen stays there until the new sheet is cut.
        private func show(_ position: BookPosition) {
            pendingPosition = position
            currentChapterId = position.chapterId

            guard let bookLayout else { return }

            generation += 1
            fillingForward = nil
            fillingBackward = nil

            let generation = generation

            showing?.cancel()
            showing = Task { [weak self] in
                guard let self else { return }

                let sheet = await self.sheet(at: position, in: bookLayout)

                guard generation == self.generation else { return }
                guard
                    let sheet
                else {
                    self.errorMessage = String(localized: "Couldn’t load this chapter.")
                    self.isLoading = false
                    return
                }

                self.sheets = [ sheet ]
                self.sheetIndex = 0
                self.isWaitingForSheet = false
                self.pendingPosition = nil
                self.isLoading = false
                self.settle()
            }
        }

        /// Takes the reader to a passage found by searching, looked for where the chapter now sets it.
        private func show(passage words: String, near: Int, in chapterId: Int) {
            currentChapterId = chapterId
            passageAsked += 1

            let asked = passageAsked

            Task { [weak self] in
                guard let self else { return }

                let built = await self.bookLayout?.layout(of: chapterId)
                let place = built.flatMap { self.place(of: words, near: near, in: $0) }

                guard asked == self.passageAsked else { return }

                self.foundPlace = place.map { FoundPlace(chapterId: chapterId, range: $0) }
                self.show(BookPosition(chapterId: chapterId, offset: place?.lowerBound ?? near))
            }
        }

        /// Counts passages asked for, so a slow answer to an old one does not land over a newer one.
        @ObservationIgnored
        private var passageAsked = 0

        /// Turns to the sheet after this one, waiting for it where it has not been cut yet.
        func turnForward() {
            guard currentSheet != nil else { return }
            guard
                !sheets.indices.contains(sheetIndex + 1)
            else {
                sheetIndex += 1
                return settle()
            }

            wait(for: 1)
        }

        /// Turns to the sheet before this one, waiting for it where it has not been cut yet.
        func turnBack() {
            guard currentSheet != nil else { return }
            guard
                sheetIndex == 0
            else {
                sheetIndex -= 1
                return settle()
            }

            wait(for: -1)
        }

        /// Lands a turn on a sheet still being cut: a blank page for the moment the cutting takes.
        private func wait(for step: Int) {
            let generation = generation

            isWaitingForSheet = true

            Task { [weak self] in
                guard let self else { return }

                if step > 0 { await self.fillForward() } else { await self.fillBackward() }

                guard generation == self.generation, self.isWaitingForSheet else { return }

                self.isWaitingForSheet = false

                guard self.sheets.indices.contains(self.sheetIndex + step) else { return }

                self.sheetIndex += step
                self.settle()
            }
        }

        /// Everything that follows the reader arriving on a sheet.
        private func settle() {
            guard let sheet = currentSheet else { return }

            currentChapterId = sheet.start.chapterId

            for page in sheet.pages {
                for piece in page.pieces { rememberWords(in: piece.layout) }
            }

            rememberPages()

            savePosition(now: sheet.start.chapterId != wroteChapterId)
            wroteChapterId = sheet.start.chapterId
            reportProgress()
            countBookPages()
            trim()

            Task { [weak self] in
                await self?.fillForward()
                await self?.fillBackward()
                await self?.readAheadOfTheReader()
            }
        }

        /// Cuts the sheet after the last one known, where the reader could turn onto it.
        private func fillForward() async {
            if let running = fillingForward { return await running.value }

            let task = Task { [weak self] in
                guard let self else { return }

                await self.extendForward()
            }

            fillingForward = task
            await task.value

            if fillingForward == task { fillingForward = nil }
        }

        private func extendForward() async {
            let generation = generation

            guard
                let bookLayout,
                let last = sheets.last,
                sheets.count == sheetIndex + 1 || isWaitingForSheet,
                let next = await sheet(after: last, in: bookLayout),
                generation == self.generation,
                sheets.last == last
            else { return }

            sheets.append(next)
        }

        /// Cuts the sheet before the first one known, where the reader could turn back onto it.
        private func fillBackward() async {
            if let running = fillingBackward { return await running.value }

            let task = Task { [weak self] in
                guard let self else { return }

                await self.extendBackward()
            }

            fillingBackward = task
            await task.value

            if fillingBackward == task { fillingBackward = nil }
        }

        private func extendBackward() async {
            let generation = generation

            guard
                let bookLayout,
                let first = sheets.first,
                sheetIndex == 0,
                let previous = await sheet(before: first, in: bookLayout),
                generation == self.generation,
                sheets.first == first
            else { return }

            sheets.insert(previous, at: 0)
            sheetIndex += 1
        }

        /// The sheet that opens at a position.
        private func sheet(at position: BookPosition, in layout: BookLayout) async -> Sheet? {
            guard let first = await layout.page(at: position) else { return nil }

            return Sheet(pages: await pages(following: first, in: layout))
        }

        private func sheet(after sheet: Sheet, in layout: BookLayout) async -> Sheet? {
            guard let last = sheet.pages.last, let next = await layout.page(after: last) else { return nil }

            return Sheet(pages: await pages(following: next, in: layout))
        }

        private func sheet(before sheet: Sheet, in layout: BookLayout) async -> Sheet? {
            var pages: [BookPage] = []
            var first = sheet.pages[0]

            while pages.count < columns, let previous = await layout.page(before: first) {
                pages.insert(previous, at: 0)
                first = previous
            }

            return pages.isEmpty ? nil : Sheet(pages: pages)
        }

        /// A page and as many after it as a sheet holds.
        private func pages(following first: BookPage, in layout: BookLayout) async -> [BookPage] {
            var pages = [ first ]

            while pages.count < columns, let last = pages.last, let next = await layout.page(after: last) {
                pages.append(next)
            }

            return pages
        }

        /// Keeps the sheets, the chapters and their text to the few around the reader.
        private func trim() {
            let kept = Self.sheetsKept

            if sheetIndex > kept {
                sheets.removeFirst(sheetIndex - kept)
                sheetIndex = kept
            }

            if sheets.count - sheetIndex - 1 > kept { sheets.removeLast(sheets.count - sheetIndex - 1 - kept) }

            let shown = Set(sheets.flatMap(\.pages).flatMap { [ $0.start.chapterId, $0.end.chapterId ] })
            let readable = readableChapters
            let near = shown.union(shown.flatMap { id -> [Int] in
                guard let index = readable.firstIndex(where: { $0.id == id }) else { return [] }

                return readable[max(0, index - 1) ... min(readable.count - 1, index + 1)].map(\.id)
            })

            bookLayout?.keep(only: shown)
            parsed = parsed.filter { near.contains($0.key) }
        }

        /// How many sheets either side of the reader's are kept to turn back and forth through.
        private static let sheetsKept = 8

        /// Reads the text of the chapters either side of the reader's, so reaching one costs a page turn
        /// rather than a round trip to the service.
        private func readAheadOfTheReader() async {
            guard let index = currentIndex else { return }

            let readable = readableChapters

            for neighbour in [ index + 1, index - 1 ] where readable.indices.contains(neighbour) {
                _ = await content(for: readable[neighbour].id)
            }
        }

        /// The chapter's text: prepared already, else stored on the device, else from the service.
        func content(for chapterId: Int) async -> ChapterContent? {
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
            guard let position = storedPosition else { return }

            let overall = bookProgress
            positionSaver?.cancel()
            positionSaver = Task { [store, workId] in
                if !now {
                    try? await Task.sleep(for: .milliseconds(400))

                    guard !Task.isCancelled else { return }
                }

                await store.store(position: .init(
                    workId: workId,
                    chapterId: position.chapterId,
                    characterOffset: position.offset,
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

            guard let position = storedPosition else { return }

            let overall = bookProgress

            Task { [store, workId] in
                await store.store(position: .init(
                    workId: workId,
                    chapterId: position.chapterId,
                    characterOffset: position.offset,
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
            guard session.isSignedIn, let position = currentSheet?.end, position.offset >= 0 else { return }

            let chapterProgress = share(of: position)

            guard force || chapterProgress - lastReportedProgress >= 0.05 || chapterProgress >= 0.999 else { return }

            lastReportedProgress = chapterProgress
            let overall = progress(at: position)

            Task { [session, workId, sessionId] in
                await session.loaders.report(
                    ReadingPosition(workId: workId, chapterId: position.chapterId, characterOffset: 0, updatedAt: .now),
                    chapterProgress: chapterProgress,
                    bookProgress: overall,
                    sessionId: sessionId
                )
            }
        }

        /// How far into the whole book the reader is: the end of the sheet in front of them. The library
        /// draws its ring from this, since the service keeps no progress of its own.
        private var bookProgress: Double { currentSheet.map { progress(at: $0.end) } ?? 0 }
    }
}
