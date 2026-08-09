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

        @ObservationIgnored
        private var shelfByWork: [Int: LibraryState] = [:]

        @ObservationIgnored
        private let session: SessionStore

        init(session: SessionStore) {
            self.session = session
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

            await reload()
            await sweepForNewChaptersIfDue()
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
                let library = try await session.client.userLibrary(page: 1, pageSize: 200)
                let entries = library.worksInLibrary

                shelfByWork = Dictionary(
                    entries.map { ($0.id, $0.inLibraryState ?? .none) },
                    uniquingKeysWith: { first, _ in first }
                )
                works = entries.map(WorkSummary.init)
                counts = Dictionary(
                    LibraryState.shelves.compactMap { state in
                        library.count(for: state).map { (state, $0) }
                    },
                    uniquingKeysWith: { first, _ in first }
                )
                hasLoaded = true
            } catch let error as AuthorTodayError {
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = "Couldn’t load your library."
            }

            isLoading = false
        }
    }
}
