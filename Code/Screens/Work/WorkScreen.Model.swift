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

        /// Where this device left off, which is what says how much of each chapter has been read.
        private(set) var position: LocalStore.ReadingPosition?
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

        /// How far the reader has got in one chapter.
        ///
        /// The device keeps one position per book, so the rest is arithmetic on the chapter order:
        /// everything before the chapter it names has been read, everything after it hasn't.
        enum ChapterState: Equatable {
            case unread
            case reading(Double)
            case read
        }

        func state(of chapter: ChapterInfo) -> ChapterState {
            guard
                let currentId = positionChapterId,
                let current = chapters.firstIndex(where: { $0.id == currentId }),
                let index = chapters.firstIndex(where: { $0.id == chapter.id })
            else { return .unread }
            guard index >= current else { return .read }
            guard index == current else { return .unread }

            let progress = positionProgress ?? 0
            return progress >= WorkSummary.readThreshold ? .read : .reading(progress)
        }

        /// The chapter the reader is in: this device's own position, or the service's if it has none.
        private var positionChapterId: Int? { position?.chapterId ?? details?.lastChapterId }

        private var positionProgress: Double? {
            guard
                let position,
                let chapter = chapters.first(where: { $0.id == position.chapterId }),
                let length = chapter.textLength,
                length > 0
            else { return details?.lastChapterProgress }

            return min(1, max(0, Double(position.characterOffset) / Double(length)))
        }

        var readableChapters: [ChapterInfo] { chapters.filter(\.isReadable) }

        /// The book is sold, and part of it is closed to this reader. That is what not having bought it
        /// looks like from the outside, and it holds where the service's own purchase flag doesn't
        /// reach: the flag is missing for a guest, and missing means nothing rather than "no".
        var isLockedByPrice: Bool {
            guard summary?.isPaid == true else { return false }

            return chapters.contains { !$0.isReadable }
        }

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

            position = await store.position(workId: workId)
            storedSummary = stored.summary
            tags = stored.tags
            isInLibrary = (stored.summary.libraryState ?? .none) != .none
            chapters = await store.chapters(workId: workId)
        }

        /// Reading moves the position, so coming back from the reader has to pick the new one up.
        func refreshPosition() async {
            position = await store.position(workId: workId)
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
