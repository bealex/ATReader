//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
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
            /// The last page this chapter has to itself: not the one the next chapter starts on.
            case lastOfItsOwn
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
        }

        let workId: Int
        let workTitle: String

        private(set) var book: WorkSummary?
        private(set) var chapters: [ChapterInfo] = []
        private(set) var currentChapterId: Int?
        private(set) var layout: ChapterLayout?
        private(set) var isLoading = false
        private(set) var errorMessage: String?

        /// True when the last request to the service failed and the reader is running off the device.
        private(set) var isOffline = false

        /// How far a long chapter has got through being laid out, `0…1`. Short chapters never set it:
        /// they are done before a reader could read a progress bar.
        private(set) var paginationProgress: Double?

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
        private let store: LocalStore

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

        @ObservationIgnored
        private var positionSaver: Task<Void, Never>?

        init(
            workId: Int,
            workTitle: String,
            initialChapterId: Int?,
            session: SessionStore,
            store: LocalStore = .shared
        ) {
            self.workId = workId
            self.workTitle = workTitle
            self.requestedChapterId = initialChapterId
            self.session = session
            self.store = store
        }

        // MARK: - Where the reader is

        var readableChapters: [ChapterInfo] { chapters.filter(\.isReadable) }

        private var currentIndex: Int? {
            readableChapters.firstIndex { $0.id == currentChapterId }
        }

        var previousChapter: ChapterInfo? {
            guard let index = currentIndex, index > 0 else { return nil }

            return readableChapters[index - 1]
        }

        var nextChapter: ChapterInfo? {
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

        private func textIndex(for page: Int) -> Int { page - titlePageCount }

        /// True when this chapter begins part-way down the page the one before it ended on.
        private var runsOnFromPrevious: Bool { (layout?.startOffset ?? 0) > 0 }

        /// True when the chapter after this one begins on this chapter's last page.
        private var nextRunsOn: Bool {
            guard let next = nextChapter else { return false }

            return (layouts[next.id]?.startOffset ?? 0) > 0
        }

        /// What sits at `index`, which runs from `-1` to ``pageCount`` so a turn can show the page in the
        /// neighbouring chapter it is about to land on.
        func page(at index: Int) -> Page {
            if index < 0 { return pageBefore() }

            if hasTitlePage, index == 0 { return .title }

            let page = textIndex(for: index)

            guard let layout, layout.pageRanges.indices.contains(page) else { return pageAfter(at: index) }

            var pieces: [Piece] = []

            if page == 0, runsOnFromPrevious, let previous = previousChapter, let before = layouts[previous.id] {
                pieces.append(Piece(layout: before, page: before.pageCount - 1))
            }

            pieces.append(Piece(layout: layout, page: page))

            if page == layout.pageCount - 1, nextRunsOn, let next = nextChapter, let after = layouts[next.id] {
                pieces.append(Piece(layout: after, page: 0))
            }

            return .text(pieces)
        }

        /// The page before this chapter's first: the previous chapter's last, unless this chapter starts
        /// on that very page, in which case it is the one before that.
        private func pageBefore() -> Page {
            guard let previous = previousChapter, let neighbour = layouts[previous.id] else { return .blank }

            let target = neighbour.pageCount - 1 - (runsOnFromPrevious ? 1 : 0)

            guard target >= 0 else { return .blank }

            return .text([ Piece(layout: neighbour, page: target) ])
        }

        /// The page after this chapter's last: the next chapter's first, unless it already began on the
        /// page this chapter ended on.
        private func pageAfter(at index: Int) -> Page {
            guard index >= pageCount, let next = nextChapter, let after = layouts[next.id] else { return .blank }

            let target = after.startOffset > 0 ? 1 : 0

            guard after.pageRanges.indices.contains(target) else { return .blank }

            return .text([ Piece(layout: after, page: target) ])
        }

        /// The footer for one page: where that page sits in its chapter, and the chapter in the book.
        ///
        /// Every page names itself rather than the reader's position, because the pages either side of
        /// this one are on screen during a turn and belong to their own chapters.
        func caption(at index: Int) -> String? {
            switch page(at: index) {
                case .title:
                    guard let layout else { return nil }

                    return caption(chapterId: layout.chapterId, number: 1, total: layout.pageCount + 1)
                case let .text(pieces):
                    // A shared page names the chapter that starts on it: that is the news.
                    guard let piece = pieces.last else { return nil }

                    let extra = position(of: piece.layout.chapterId) == 0 ? 1 : 0

                    return caption(
                        chapterId: piece.layout.chapterId,
                        number: piece.page + 1 + extra,
                        total: piece.layout.pageCount + extra
                    )
                case .blank:
                    return nil
            }
        }

        private func caption(chapterId: Int, number: Int, total: Int) -> String? {
            guard let position = position(of: chapterId), total > 0 else { return nil }

            return String(localized: "Chapter \(position + 1)/\(readableChapters.count) · page \(number)/\(total)")
        }

        private func position(of chapterId: Int) -> Int? {
            readableChapters.firstIndex { $0.id == chapterId }
        }

        // MARK: - Layout

        /// Adopts a new page size or reading style, keeping the reader's place.
        func apply(context newContext: ChapterLayout.Context) {
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
        }

        // MARK: - Opening the book

        func loadIfNeeded() async {
            guard !hasLoaded else { return }

            hasLoaded = true
            isLoading = true

            // Opening a book counts as seeing whatever the daily sweep flagged for it.
            await UpdateBadge.clear(workId: workId)

            book = await store.work(id: workId)?.summary
            chapters = await store.chapters(workId: workId)
            let position = await store.position(workId: workId)

            if !chapters.isEmpty { openTarget(position: position) }

            await refreshContents()

            if currentChapterId == nil { openTarget(position: position) }

            isLoading = layout == nil && errorMessage == nil
            await refreshBook()
        }

        /// Picks the chapter to open: the one asked for, else the one the reader stopped in, else the first.
        private func openTarget(position: LocalStore.ReadingPosition?) {
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

        private func refreshContents() async {
            do {
                let fetched = try await session.client.workContents(id: workId)
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
            guard book == nil else { return }
            guard let details = try? await session.client.workDetails(id: workId) else { return }

            let summary = WorkSummary(details)
            book = summary
            await store.store(work: summary, tags: details.tags)
        }

        /// Asks the service where this reader stopped and keeps the session id for progress reports.
        private func startSession(chapterId: Int) async {
            guard session.isSignedIn else { return }
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

            if let prepared = layouts[chapterId] { return install(prepared, anchor: anchor) }

            layout = nil
            isLoading = true
            Task { await load(chapterId: chapterId, anchor: anchor) }
        }

        func goToNextChapter() {
            guard let next = nextChapter else { return }

            // Where the next chapter began on this chapter's last page, its first page is the one the
            // reader is already looking at.
            open(chapterId: next.id, anchor: nextRunsOn ? .page(1) : .first)
        }

        func goToPreviousChapter() {
            guard let previous = previousChapter else { return }

            open(chapterId: previous.id, anchor: .lastOfItsOwn)
        }

        private func load(chapterId: Int, anchor: PageAnchor) async {
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
                startOffset: 0,
                reportsProgress: true
            )
            paginationProgress = nil

            guard let built else { return }

            install(built, anchor: anchor)
        }

        private func install(_ built: ChapterLayout, anchor: PageAnchor) {
            layouts[built.chapterId] = built
            layout = built
            currentChapterId = built.chapterId

            switch anchor {
                case .first:
                    currentPage = 0
                case let .page(page):
                    currentPage = min(max(0, page + titlePageCount), max(0, pageCount - 1))
                case .lastOfItsOwn:
                    currentPage = max(0, pageCount - 1 - (nextRunsOn ? 1 : 0))
                case let .offset(offset):
                    currentPage = built.pageIndex(containing: offset) + titlePageCount
            }

            isLoading = false
            errorMessage = nil
            savePosition()
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
            guard let index = currentIndex, let current = layout else { return }

            trimCaches(around: index)
            prefetch?.cancel()
            prefetch = Task { [weak self] in
                await self?.prepareAhead(from: index, after: current)
                await self?.prepareBehind(from: index)
            }
        }

        private func prepareAhead(from index: Int, after current: ChapterLayout) async {
            let chapters = readableChapters
            var previous = current

            for position in (index + 1) ..< min(index + 3, chapters.count) {
                let id = chapters[position].id
                let offset = startOffset(after: previous)

                // A chapter opened from the contents was laid out on a page of its own. Reading into it
                // from the chapter before, it belongs on that chapter's last page instead.
                if let existing = layouts[id], existing.startOffset == offset {
                    previous = existing
                    continue
                }

                guard !Task.isCancelled else { return }
                guard let built = await prepare(chapterId: id, startOffset: offset) else { return }

                previous = built
            }
        }

        private func prepareBehind(from index: Int) async {
            guard index > 0 else { return }

            let id = readableChapters[index - 1].id

            guard layouts[id] == nil, !Task.isCancelled else { return }

            _ = await prepare(chapterId: id, startOffset: 0)
        }

        @discardableResult
        private func prepare(chapterId: Int, startOffset: CGFloat) async -> ChapterLayout? {
            guard let context, let content = await content(for: chapterId) else { return nil }
            guard
                let built = await makeLayout(
                    chapterId: chapterId,
                    content: content,
                    context: context,
                    startOffset: startOffset,
                    reportsProgress: false
                )
            else { return nil }

            layouts[chapterId] = built
            return built
        }

        /// Where a chapter starts on the page the one before it ended on, and how far down.
        ///
        /// A chapter only runs on when what is left of the page holds a decent piece of it; a heading
        /// with two lines under it belongs on the next page instead.
        private func startOffset(after previous: ChapterLayout) -> CGFloat {
            guard let context, previous.pageCount > 1 else { return 0 }

            let chapterGap = context.style.fontSize * 2.5
            let lineHeight = context.style.fontSize + context.style.lineSpacing
            let free = previous.tailFreeSpace - chapterGap

            guard free >= max(lineHeight * 6, context.textSize.height * 0.25) else { return 0 }

            return context.textSize.height - previous.tailFreeSpace + chapterGap
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
                heading: ChapterHeading.make(position: position, title: title),
                context: context,
                startOffset: startOffset,
                onProgress: reportsProgress ? report : nil
            )

            // The style may have moved on while this was being measured.
            guard context == self.context else { return nil }

            return built
        }

        /// The chapter's text: prepared already, else stored on the device, else from the service.
        private func content(for chapterId: Int) async -> ChapterContent? {
            if let cached = parsed[chapterId] { return cached }

            if let stored = await store.body(workId: workId, chapterId: chapterId) {
                let prepared = await ChapterContent.prepare(html: stored.html)
                parsed[chapterId] = prepared
                return prepared
            }

            do {
                let chapter = try await session.client.chapterText(workId: workId, chapterId: chapterId)
                await store.store(body: chapter, workId: workId)
                let prepared = await ChapterContent.prepare(html: chapter.html)
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
        private func savePosition() {
            guard let layout, let chapterId = currentChapterId else { return }

            let offset = layout.characterOffset(ofPage: textIndex(for: currentPage))
            positionSaver?.cancel()
            positionSaver = Task { [store, workId] in
                try? await Task.sleep(for: .milliseconds(400))

                guard !Task.isCancelled else { return }

                await store.store(position: .init(
                    workId: workId,
                    chapterId: chapterId,
                    characterOffset: offset,
                    updatedAt: .now
                ))
            }
        }

        /// Syncs the position upstream in coarse steps rather than on every page.
        private func reportProgress() {
            guard pageCount > 0, session.isSignedIn, let chapterId = currentChapterId else { return }

            let chapterProgress = Double(currentPage + 1) / Double(pageCount)

            guard chapterProgress - lastReportedProgress >= 0.05 || chapterProgress >= 0.999 else { return }

            lastReportedProgress = chapterProgress
            let overall = overallProgress(chapterProgress: chapterProgress)

            Task { [session, workId, sessionId] in
                try? await session.client.updateProgress(
                    workId: workId,
                    chapterId: chapterId,
                    workProgress: overall,
                    chapterProgress: chapterProgress,
                    sessionId: sessionId
                )
            }
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
