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

        func newChapters(for workId: Int) -> Int { UpdateBadge.newChapters(for: workId) }

        func dismissError() { errorMessage = nil }

        func loadIfNeeded() async {
            guard !hasLoaded else { return }

            await showStoredLibrary()
            await reload()
            await adoptServerPositions()
            await sweepForNewChaptersIfDue()
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

        /// The daily check also runs in the foreground, so the badge is current even when the system
        /// never granted a background window.
        private func sweepForNewChaptersIfDue() async {
            let lastChecked = UpdateBadge.lastCheckedAt
            let isDue = lastChecked.map { Date.now.timeIntervalSince($0) > BackgroundRefresh.interval }

            guard isDue != false else { return }

            _ = try? await ChapterUpdateService(client: session.client).check()
            newChapterRevision += 1
        }

        /// Bumped after a sweep so the list redraws with the fresh per-book counts.
        private(set) var newChapterRevision = 0

        func reload() async {
            guard !isLoading else { return }

            isLoading = true
            errorMessage = nil

            defer { isLoading = false }

            do {
                let library = try await session.client.fullUserLibrary()
                let entries = library.worksInLibrary.map(WorkSummary.init)
                await store.replaceLibrary(with: entries)
                // Read back rather than painting what arrived: the service carries no progress this
                // device made, so its copy would undo a book marked read the moment it landed.
                let merged = await store.works()
                apply(entries: merged.isEmpty ? entries : merged)
                isOffline = false
                hasLoaded = true
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
            try? await session.client.updateLibraryState(workIds: [ work.id ], state: .finished)

            if let index = works.firstIndex(where: { $0.id == work.id }) {
                works[index].libraryState = .finished
                await store.store(work: works[index])
            }

            guard let last = await contents(of: work.id).last(where: \.isReadable) else { return }

            await store.store(position: .init(
                workId: work.id,
                chapterId: last.id,
                // Past the end when the chapter's length is unknown; the reader clamps to its last page.
                characterOffset: last.textLength ?? .max,
                updatedAt: .now
            ))
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

            guard stored.isEmpty else { return stored }
            guard let fetched = try? await session.client.workContents(id: workId) else { return [] }

            await store.store(chapters: fetched, workId: workId)
            return fetched.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
        }

        /// Takes a book out of the reader's library. Removing it is the one thing left that the
        /// service's library state is good for.
        func remove(_ work: WorkSummary) async {
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
            works = entries
            Task { await CoverCache.shared.prefetch(entries.compactMap(\.coverURL)) }
        }
    }
}
