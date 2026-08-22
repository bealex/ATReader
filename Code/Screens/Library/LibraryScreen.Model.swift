//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import Foundation

extension LibraryScreen {
    @Observable @MainActor
    final class Model {
        /// One heading of the list: an author, and one of their series where the books belong to one.
        struct Group: Identifiable {
            let id: String
            let author: String
            let series: String?
            let works: [WorkSummary]
            /// The last time any book here was read or gained a chapter, which is what orders the list.
            let recency: Date
        }

        /// Which shelf the list is showing. `nil` means everything the reader has added; the books
        /// being read now are what the library opens on.
        var shelf: LibraryState? = .reading
        var searchText = ""

        private(set) var works: [WorkSummary] = []
        private(set) var counts: [LibraryState: Int] = [:]
        private(set) var isLoading = false
        private(set) var errorMessage: String?
        private(set) var hasLoaded = false

        /// True while the list is the stored one and the service could not be reached.
        private(set) var isOffline = false

        @ObservationIgnored
        private var shelfByWork: [Int: LibraryState] = [:]

        @ObservationIgnored
        private let session: SessionStore

        @ObservationIgnored
        private let store: LocalStore

        init(session: SessionStore, store: LocalStore = .shared) {
            self.session = session
            self.store = store
        }

        /// The rows after the shelf filter and the local title/author filter.
        var visibleWorks: [WorkSummary] {
            var result = works

            if let shelf {
                result = result.filter { shelfByWork[$0.id] == shelf }
            }

            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            guard !query.isEmpty else { return result }

            return result.filter {
                $0.title.lowercased().contains(query) || $0.authorLine.lowercased().contains(query)
            }
        }

        /// By author, and within an author by series, with whatever was last read or last updated on top.
        var groups: [Group] {
            let byHeading = Dictionary(grouping: visibleWorks) { work in
                Heading(author: work.authorLine, series: work.seriesTitle?.isEmpty == false ? work.seriesTitle : nil)
            }

            return
                byHeading
                .map { heading, works in
                    Group(
                        id: "\(heading.author)|\(heading.series ?? "")",
                        author: heading.author,
                        series: heading.series,
                        // A series reads in its own order; loose titles by an author read newest first.
                        works: works.sorted(by: heading.series == nil ? Self.byRecency : Self.withinSeries),
                        recency: works.map(Self.recency).max() ?? .distantPast
                    )
                }
                .sorted(by: Self.byHeading)
        }

        private struct Heading: Hashable {
            let author: String
            let series: String?
        }

        private static func recency(_ work: WorkSummary) -> Date {
            max(work.lastReadTime ?? .distantPast, work.lastUpdateTime ?? .distantPast)
        }

        private static func byRecency(_ left: WorkSummary, _ right: WorkSummary) -> Bool {
            guard
                recency(left) == recency(right)
            else {
                return recency(left) > recency(right)
            }

            return left.title.localizedStandardCompare(right.title) == .orderedAscending
        }

        private static func withinSeries(_ left: WorkSummary, _ right: WorkSummary) -> Bool {
            guard
                left.seriesOrder == right.seriesOrder
            else {
                return (left.seriesOrder ?? .max) < (right.seriesOrder ?? .max)
            }

            return left.title.localizedStandardCompare(right.title) == .orderedAscending
        }

        private static func byHeading(_ left: Group, _ right: Group) -> Bool {
            guard
                left.recency == right.recency
            else {
                return left.recency > right.recency
            }
            guard
                left.author == right.author
            else {
                return left.author.localizedStandardCompare(right.author) == .orderedAscending
            }
            guard let leftSeries = left.series else { return right.series != nil }
            guard let rightSeries = right.series else { return false }

            return leftSeries.localizedStandardCompare(rightSeries) == .orderedAscending
        }

        /// Books with a position to return to, the most recently updated first: a book the author has
        /// just added a chapter to is the one worth picking up.
        var continueReading: [WorkSummary] {
            works
                .filter { $0.hasStartedReading && ($0.readingProgress ?? 0) < 1 }
                .sorted { ($0.lastUpdateTime ?? .distantPast) > ($1.lastUpdateTime ?? .distantPast) }
                .prefix(10)
                .map { $0 }
        }

        func count(for shelf: LibraryState?) -> Int? {
            guard let shelf else { return works.isEmpty ? nil : works.count }

            return counts[shelf]
        }

        func newChapters(for workId: Int) -> Int { UpdateBadge.newChapters(for: workId) }

        func dismissError() { errorMessage = nil }

        func loadIfNeeded() async {
            guard !hasLoaded else { return }

            await showStoredLibrary()
            await reload()
            await sweepForNewChaptersIfDue()
        }

        /// Draws the shelf the device already has before the service is asked anything, so the library
        /// opens instantly and opens at all with no network.
        private func showStoredLibrary() async {
            let stored = await store.works()

            guard !stored.isEmpty, works.isEmpty else { return }

            apply(entries: stored, counts: nil)
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

            do {
                let library = try await session.client.fullUserLibrary()
                let entries = library.worksInLibrary.map(WorkSummary.init)
                apply(entries: entries, counts: library)
                await store.replaceLibrary(with: entries)
                isOffline = false
                hasLoaded = true
            } catch let error as AuthorTodayError where error.requiresReauthentication {
                errorMessage = error.localizedDescription
            } catch {
                // The stored shelf is already on screen; say the list is stale rather than replacing it
                // with an error.
                isOffline = true

                if works.isEmpty { errorMessage = String(localized: "Couldn’t load your library.") }
            }

            isLoading = false
        }

        /// Moves one book to another shelf, or off the shelves entirely with ``LibraryState/none``.
        func move(_ work: WorkSummary, to state: LibraryState) async {
            guard session.isSignedIn, shelfByWork[work.id] != state else { return }

            let previous = shelfByWork[work.id] ?? .none
            apply(state: state, to: work.id)

            do {
                try await session.client.updateLibraryState(workIds: [ work.id ], state: state)
                await persistShelves()
            } catch {
                apply(state: previous, to: work.id)
                // The shelf the service reports wins, so a refused move leaves a truthful list behind.
                // The message goes on after the reload, which clears it.
                await reload()
                errorMessage = error.localizedDescription
            }
        }

        private func apply(state: LibraryState, to workId: Int) {
            guard let index = works.firstIndex(where: { $0.id == workId }) else { return }

            if state == .none {
                works.remove(at: index)
                shelfByWork[workId] = nil
            } else {
                works[index].libraryState = state
                shelfByWork[workId] = state
            }

            counts = Dictionary(
                LibraryState.shelves.map { state in (state, works.filter { shelfByWork[$0.id] == state }.count) },
                uniquingKeysWith: { first, _ in first }
            )
        }

        private func persistShelves() async {
            await store.replaceLibrary(with: works)
        }

        private func apply(entries: [WorkSummary], counts library: UserLibrary?) {
            shelfByWork = Dictionary(
                entries.map { ($0.id, $0.libraryState ?? .none) },
                uniquingKeysWith: { first, _ in first }
            )
            works = entries
            Task { await CoverCache.shared.prefetch(entries.compactMap(\.coverURL)) }

            guard let library else { return }

            counts = Dictionary(
                LibraryState.shelves.compactMap { state in
                    library.count(for: state).map { (state, $0) }
                },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }
}
