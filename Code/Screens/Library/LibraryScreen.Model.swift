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

        /// Latest book in the series first, which is the one with a chapter still arriving. Titles
        /// compare numerically, so a series with no order on it still lands newest first.
        private static func withinSeries(_ left: WorkSummary, _ right: WorkSummary) -> Bool {
            guard
                left.seriesOrder == right.seriesOrder
            else {
                return (left.seriesOrder ?? .min) > (right.seriesOrder ?? .min)
            }

            return left.title.localizedStandardCompare(right.title) == .orderedDescending
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
            await sweepForNewChaptersIfDue()
        }

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

            do {
                let library = try await session.client.fullUserLibrary()
                let entries = library.worksInLibrary.map(WorkSummary.init)
                apply(entries: entries)
                await store.replaceLibrary(with: entries)
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

            isLoading = false
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
