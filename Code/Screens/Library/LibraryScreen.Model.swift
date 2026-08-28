//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import Foundation

extension LibraryScreen {
    @Observable @MainActor
    final class Model {
        /// One heading of the list: a series, or a single book that belongs to none. A series can carry
        /// more than one author, so the authors are left to the rows.
        struct Group: Identifiable {
            let id: String
            let series: String?
            let works: [WorkSummary]
            /// The last time any book here gained anything, which is what orders the list.
            let updated: Date
        }

        /// What the list is showing. The service's shelves say nothing dependable about where a reader
        /// has got to, so the app decides this from what has been written and what has been read.
        enum Filter: String, CaseIterable, Identifiable {
            /// The author is still writing it, or there is text left to read. Both mean "open me".
            case reading
            /// Written to its end and read to its end.
            case finished
            case everything

            var id: String { rawValue }

            var title: String {
                switch self {
                    case .reading: String(localized: "Reading")
                    case .finished: String(localized: "Finished")
                    case .everything: String(localized: "All books")
                }
            }

            var systemImage: String {
                switch self {
                    case .reading: "book"
                    case .finished: "checkmark.circle"
                    case .everything: "books.vertical"
                }
            }

            func includes(_ work: WorkSummary) -> Bool {
                switch self {
                    case .reading: !work.isFinishedReading
                    case .finished: work.isFinishedReading
                    case .everything: true
                }
            }
        }

        var filter: Filter = .reading
        var searchText = ""

        private(set) var works: [WorkSummary] = []
        private(set) var isLoading = false
        private(set) var errorMessage: String?
        private(set) var hasLoaded = false

        /// True while the list is the stored one and the service could not be reached.
        private(set) var isOffline = false

        /// True while a picked file is being read into the library.
        private(set) var isImporting = false

        /// How far each book still being prepared has got, so the shelf can say so.
        private(set) var processing: [Int: BookProcessor.Progress] = [:]

        @ObservationIgnored
        private let session: SessionStore

        @ObservationIgnored
        private let store: LocalStore

        init(session: SessionStore, store: LocalStore = .shared) {
            self.session = session
            self.store = store
        }

        /// The rows after the filter and the local title/author search.
        var visibleWorks: [WorkSummary] {
            let result = works.filter(filter.includes)
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            guard !query.isEmpty else { return result }

            return result.filter {
                $0.title.lowercased().contains(query) || $0.authorLine.lowercased().contains(query)
            }
        }

        /// Books in a series stand together under its name, latest first; a book in no series stands
        /// alone. Whatever was last read or last gained a chapter comes first.
        var groups: [Group] {
            let visible = visibleWorks
            let series = Dictionary(grouping: visible.filter { $0.series != nil }) { $0.series ?? "" }

            let grouped = series.map { title, works in
                Group(
                    id: "series:\(title)",
                    series: title,
                    works: works.sorted(by: Self.withinSeries),
                    updated: works.map(Self.updated).max() ?? .distantPast
                )
            }
            let alone = visible.filter { $0.series == nil }.map { work in
                Group(id: "work:\(work.id)", series: nil, works: [ work ], updated: Self.updated(work))
            }

            return (grouped + alone).sorted(by: Self.byUpdate)
        }

        /// When the service last changed the book. Reading it is not a change to it, so the list holds
        /// still while the reader reads rather than shuffling under them.
        private static func updated(_ work: WorkSummary) -> Date { work.lastUpdateTime ?? .distantPast }

        /// Latest book in the series first, which is the one with a chapter still arriving. Titles
        /// compare numerically, so a series the service gives no order for still lands newest first.
        private static func withinSeries(_ left: WorkSummary, _ right: WorkSummary) -> Bool {
            guard
                left.seriesOrder == right.seriesOrder
            else {
                return (left.seriesOrder ?? .min) > (right.seriesOrder ?? .min)
            }

            return left.title.localizedStandardCompare(right.title) == .orderedDescending
        }

        /// Newest first, and books the service gives no date for keep a fixed order of their own rather
        /// than whatever the grouping happened to produce.
        private static func byUpdate(_ left: Group, _ right: Group) -> Bool {
            guard
                left.updated == right.updated
            else {
                return left.updated > right.updated
            }

            return left.id.localizedStandardCompare(right.id) == .orderedAscending
        }

        /// Counted the way the list counts, so the number beside a filter is the number of rows it opens.
        func count(for filter: Filter) -> Int? {
            guard !works.isEmpty else { return nil }

            return works.count(where: filter.includes)
        }

        /// Mirrored out of user defaults, which nothing observes, so the badges redraw when a sweep
        /// finds something.
        private(set) var newChaptersByWork: [Int: Int] = UpdateBadge.newChaptersByWork

        func newChapters(for workId: Int) -> Int { newChaptersByWork[workId] ?? 0 }

        func dismissError() { errorMessage = nil }

        // MARK: - Books from files

        /// Reads a picked file into the library and starts preparing it.
        ///
        /// The book is on the shelf and readable the moment its text is stored. Putting it through the
        /// typesetter happens behind that, so a long book doesn't hold the picker open.
        func importBook(from url: URL) async {
            isImporting = true
            errorMessage = nil

            defer { isImporting = false }

            do {
                let work = try await BookImport.import(from: url)
                await refreshFromStore()
                await prepare(workId: work.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        /// Puts a book through the typesetter behind the shelf, reporting how far it has got.
        private func prepare(workId: Int) async {
            let chapters = await store.chapters(workId: workId)

            await BookProcessor.shared.start(workId: workId, chapters: chapters)
            watch(workId: workId)
        }

        /// Follows one book's preparation until it finishes, so the shelf can show a bar against it.
        private func watch(workId: Int) {
            Task { [weak self] in
                while !Task.isCancelled {
                    guard let progress = await BookProcessor.shared.progress(of: workId) else { return }

                    self?.processing[workId] = progress.isComplete ? nil : progress

                    if progress.isComplete { return }

                    try? await Task.sleep(for: .milliseconds(400))
                }
            }
        }

        /// Takes an imported book off the device outright. Its text is here and nowhere else.
        func deleteLocalBook(_ work: WorkSummary) async {
            guard LocalBooks.isLocal(work.id) else { return }

            works.removeAll { $0.id == work.id }
            processing[work.id] = nil
            await BookProcessor.shared.stop(workId: work.id)
            await BookImport.remove(workId: work.id)
        }

        /// True for a book that came from a file rather than the service.
        func isLocal(_ work: WorkSummary) -> Bool { LocalBooks.isLocal(work.id) }

        func loadIfNeeded() async {
            guard !hasLoaded else { return }

            await showStoredLibrary()
            await reload()
            await adoptServerPositions()
        }

        /// Redraws the list from the store, without asking the service anything.
        ///
        /// Reading fills the rings, and the service knows nothing about it: the position and the
        /// progress it implies live here alone. Coming back from a book has to read them again.
        func refreshFromStore() async {
            let stored = await store.works()

            guard !stored.isEmpty else { return }

            apply(entries: stored)
            newChaptersByWork = UpdateBadge.newChaptersByWork
        }

        /// Adopts the positions the service holds where they are newer than this device's own.
        ///
        /// The service records nothing this app sends, but it does record what its own site does, so a
        /// book read on author.today opens here where it was left. Progress comes back as a percentage
        /// of the chapter, which the chapter's own length turns into the offset the reader works in.
        private func adoptServerPositions() async {
            guard session.isSignedIn else { return }
            guard
                let entries = try? await session.client.readingProgress(
                    since: .now.addingTimeInterval(-Self.positionWindow)
                )
            else { return }

            for entry in entries {
                guard let chapterId = entry.chapterId, let readAt = entry.lastReadTime else { continue }

                let mine = await store.position(workId: entry.workId)

                guard (mine?.updatedAt ?? .distantPast) < readAt else { continue }

                let length =
                    await store.chapters(workId: entry.workId)
                    .first { $0.id == chapterId }?
                    .textLength ?? 0

                await store.store(position: .init(
                    workId: entry.workId,
                    chapterId: chapterId,
                    characterOffset: Int((entry.chapterProgress ?? 0) / 100 * Double(length)),
                    updatedAt: readAt
                ))
            }
        }

        /// How far back to ask for positions. The service answers with everything touched since.
        private static let positionWindow: TimeInterval = 90 * 24 * 60 * 60

        /// Draws the library the device already has before the service is asked anything, so it opens
        /// instantly and opens at all with no network.
        private func showStoredLibrary() async {
            let stored = await store.works()

            guard !stored.isEmpty, works.isEmpty else { return }

            apply(entries: stored)
        }

        /// Looks for chapters published since the device last looked.
        ///
        /// The shelf carries no chapters, so reloading it cannot answer "is there anything new to
        /// read?" on its own. What it does carry is each book's update time, and a book whose time has
        /// moved is the only one worth asking for a table of contents. Once a day everything is walked
        /// instead, which is also what fills the offline cache.
        private func findNewChapters(since previous: [WorkSummary], in entries: [WorkSummary]) async {
            let lastChecked = UpdateBadge.lastCheckedAt
            let isDue = lastChecked.map { Date.now.timeIntervalSince($0) > BackgroundRefresh.interval } ?? true
            let books = isDue ? entries : Self.changed(from: previous, to: entries)

            guard !books.isEmpty else { return }

            _ = await ChapterUpdateService(client: session.client).sweep(
                works: books,
                // A partial pass is for the badge alone; downloading bodies is the daily pass's job.
                chapterBudget: isDue ? ChapterUpdateService.foregroundChapterBudget : 0,
                isComplete: isDue
            )
            newChaptersByWork = UpdateBadge.newChaptersByWork
            // Storing a table of contents re-derives that book's progress, so the rings are read back.
            await refreshFromStore()
        }

        /// The books the service has touched since this device last saw them, plus the ones it has
        /// never seen.
        private static func changed(from previous: [WorkSummary], to entries: [WorkSummary]) -> [WorkSummary] {
            let before = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            return entries.filter { before[$0.id]?.lastUpdateTime != $0.lastUpdateTime }
        }

        /// One sweep at a time; a second pull while one is walking would only ask the same questions.
        @ObservationIgnored
        private var sweepTask: Task<Void, Never>?

        /// The walk runs behind the list rather than under the refresh spinner: it is one request per
        /// changed book, and the shelf is already on screen.
        private func startSweep(since previous: [WorkSummary], in entries: [WorkSummary]) {
            guard sweepTask == nil else { return }

            sweepTask = Task { [weak self] in
                await self?.findNewChapters(since: previous, in: entries)
                self?.sweepTask = nil
            }
        }

        func reload() async {
            guard !isLoading else { return }

            isLoading = true
            errorMessage = nil

            defer { isLoading = false }

            do {
                let previous = works
                let library = try await session.client.fullUserLibrary()
                let entries = library.worksInLibrary.map(WorkSummary.init)
                await store.replaceLibrary(with: entries)
                // Read back rather than painting what arrived: the service carries no progress this
                // device made, so its copy would undo a book marked read the moment it landed.
                let merged = await store.works()
                apply(entries: merged.isEmpty ? entries : merged)
                isOffline = false
                hasLoaded = true
                startSweep(since: previous, in: entries)
            } catch let error as AuthorTodayError where error.requiresReauthentication {
                errorMessage = error.localizedDescription
            } catch {
                // The stored library is already on screen; say the list is stale rather than replacing
                // it with an error.
                isOffline = true

                if works.isEmpty { errorMessage = String(localized: "Couldn’t load your library.") }
            }
        }

        /// Marks a book read through: the ring fills, and the book page's chapter marks fill with it,
        /// which means putting the position at the end of the last chapter it has.
        func markAsRead(_ work: WorkSummary) async {
            if let index = works.firstIndex(where: { $0.id == work.id }) {
                works[index].readingProgress = 1
            }

            await store.store(progress: 1, workId: work.id)

            // The service keeps no progress, but it does keep a shelf, and Finished is its way of
            // saying the reader is done with a book.
            if !isLocal(work) {
                try? await session.client.updateLibraryState(workIds: [ work.id ], state: .finished)
            }

            if let index = works.firstIndex(where: { $0.id == work.id }) {
                works[index].libraryState = .finished
                await store.store(work: works[index])
            }

            guard let last = await contents(of: work.id).last(where: \.isReadable) else { return }

            let isLocalBook = isLocal(work)

            await store.store(position: .init(
                workId: work.id,
                chapterId: last.id,
                // Past the end when the chapter's length is unknown; the reader clamps to its last page.
                characterOffset: last.textLength ?? .max,
                updatedAt: .now
            ))
            guard !isLocalBook else { return }

            // The service stores no progress it is sent, so this is a courtesy rather than the record.
            try? await session.client.updateProgress(
                workId: work.id,
                chapterId: last.id,
                workProgress: 1,
                chapterProgress: 1,
                sessionId: nil
            )
        }

        /// The book's chapters as the device has them, fetched if it has none.
        private func contents(of workId: Int) async -> [ChapterInfo] {
            let stored = await store.chapters(workId: workId)

            guard stored.isEmpty, !LocalBooks.isLocal(workId) else { return stored }
            guard let fetched = try? await session.client.workContents(id: workId) else { return [] }

            await store.store(chapters: fetched, workId: workId)
            return fetched.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
        }

        /// Takes a book out of the reader's library. Removing it is the one thing left that the
        /// service's library state is good for.
        func remove(_ work: WorkSummary) async {
            guard !isLocal(work) else { return await deleteLocalBook(work) }
            guard session.isSignedIn else { return }

            works.removeAll { $0.id == work.id }

            do {
                try await session.client.updateLibraryState(workIds: [ work.id ], state: LibraryState.none)
                await persistLibrary()
            } catch {
                // The library the service holds wins, and the message goes on after the reload, which
                // clears it.
                await reload()
                errorMessage = error.localizedDescription
            }
        }

        private func persistLibrary() async {
            await store.replaceLibrary(with: works)
        }

        private func apply(entries: [WorkSummary]) {
            guard works != entries else { return }

            works = entries
            Task { await CoverCache.shared.prefetch(entries.compactMap(\.coverURL)) }
        }
    }
}
