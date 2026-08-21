//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import Foundation

extension LibraryScreen {
    @Observable @MainActor
    final class Model {
        /// Which shelf the list is showing. `nil` means everything the reader has added.
        var shelf: LibraryState?
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

        /// Books with a position to return to, most recently opened first.
        var continueReading: [WorkSummary] {
            works
                .filter { $0.hasStartedReading && ($0.readingProgress ?? 0) < 1 }
                .sorted { ($0.lastReadTime ?? .distantPast) > ($1.lastReadTime ?? .distantPast) }
                .prefix(10)
                .map { $0 }
        }

        func count(for shelf: LibraryState?) -> Int? {
            guard let shelf else { return works.isEmpty ? nil : works.count }

            return counts[shelf]
        }

        func newChapters(for workId: Int) -> Int { UpdateBadge.newChapters(for: workId) }

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
