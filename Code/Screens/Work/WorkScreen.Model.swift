//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import Foundation

extension WorkScreen {
    @Observable @MainActor
    final class Model {
        let workId: Int

        private(set) var details: WorkDetails?
        private(set) var chapters: [ChapterInfo] = []
        private(set) var tags: [String] = []
        private(set) var isLoading = false
        private(set) var errorMessage: String?
        private(set) var isInLibrary = false
        private(set) var isUpdatingLibrary = false

        @ObservationIgnored
        private let session: SessionStore

        @ObservationIgnored
        private let store: LocalStore

        @ObservationIgnored
        private var hasLoaded = false

        /// The book as the device has it, shown until the service answers and kept when it does not.
        private(set) var storedSummary: WorkSummary?

        init(workId: Int, session: SessionStore, store: LocalStore = .shared) {
            self.workId = workId
            self.session = session
            self.store = store
        }

        var summary: WorkSummary? { details.map(WorkSummary.init) ?? storedSummary }

        var readableChapters: [ChapterInfo] { chapters.filter(\.isReadable) }

        /// Where "continue" should land: the stored position, else the first readable chapter.
        var resumeChapterId: Int? {
            if let stored = details?.lastChapterId, readableChapters.contains(where: { $0.id == stored }) {
                return stored
            }

            return readableChapters.first?.id
        }

        var canRead: Bool { !readableChapters.isEmpty }

        func loadIfNeeded() async {
            guard !hasLoaded else { return }

            hasLoaded = true
            await showStored()
            await reload()
        }

        private func showStored() async {
            guard let stored = await store.work(id: workId) else { return }

            storedSummary = stored.summary
            tags = stored.tags
            isInLibrary = (stored.summary.libraryState ?? .none) != .none
            chapters = await store.chapters(workId: workId)
        }

        func reload() async {
            isLoading = true
            errorMessage = nil

            do {
                async let detailsTask = session.client.workDetails(id: workId)
                async let contentsTask = session.client.workContents(id: workId)
                let (loadedDetails, loadedChapters) = try await (detailsTask, contentsTask)

                details = loadedDetails
                chapters = loadedChapters.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
                tags = loadedDetails.tags ?? []
                isInLibrary = (loadedDetails.inLibraryState ?? .none) != .none

                await store.store(work: WorkSummary(loadedDetails), tags: tags)
                await store.store(chapters: chapters, workId: workId)
            } catch let error as AuthorTodayError where error.requiresReauthentication {
                errorMessage = error.localizedDescription
            } catch {
                // A stored copy on screen beats an error message about refreshing it.
                if storedSummary == nil { errorMessage = String(localized: "Couldn’t load this book.") }
            }

            isLoading = false
        }

        /// Puts the book in the reader's library, or takes it out. A book goes in as one being read;
        /// where it stands after that is worked out from what has been written and what has been read.
        func setInLibrary(_ inLibrary: Bool) async {
            guard session.isSignedIn, !isUpdatingLibrary else { return }

            let previous = isInLibrary

            isUpdatingLibrary = true
            isInLibrary = inLibrary

            do {
                try await session.client.updateLibraryState(
                    workIds: [ workId ],
                    state: inLibrary ? .reading : LibraryState.none
                )
            } catch {
                isInLibrary = previous
                errorMessage = error.localizedDescription
            }

            isUpdatingLibrary = false
        }
    }
}
