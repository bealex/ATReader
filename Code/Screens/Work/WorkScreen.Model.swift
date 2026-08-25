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

        /// The book as the device has it, shown before the service is asked and kept when it does not
        /// answer. Progress comes from the store rather than the service, which keeps none.
        private(set) var summary: WorkSummary?
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

        init(workId: Int, session: SessionStore, store: LocalStore = .shared) {
            self.workId = workId
            self.session = session
            self.store = store
        }

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
        private var positionChapterId: Int? { position?.chapterId ?? summary?.lastChapterId }

        private var positionProgress: Double? {
            guard
                let position,
                let chapter = chapters.first(where: { $0.id == position.chapterId }),
                let length = chapter.textLength,
                length > 0
            else { return details?.lastChapterFraction }

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

        /// Where "continue" should land: the chapter this device stopped in, then the one the service
        /// remembers, then the beginning. This device's own position comes first, because it is the only
        /// one that moves when the reader reads here.
        var resumeChapterId: Int? {
            let stopped = [ position?.chapterId, summary?.lastChapterId ].compactMap { $0 }

            return stopped.first { id in readableChapters.contains { $0.id == id } } ?? readableChapters.first?.id
        }

        var canRead: Bool { !readableChapters.isEmpty }

        func loadIfNeeded() async {
            guard !hasLoaded else { return }

            hasLoaded = true
            await refreshFromStore()
            await reload()
        }

        /// Draws the book from the store: what it says about itself, its contents, and where the reader
        /// stopped. This is also how the screen picks up a reading session it has just come back from,
        /// since the service keeps no position of its own.
        ///
        /// Each field is left alone unless it actually changed, so a refresh behind a screen the reader
        /// is already looking at moves only the parts that moved.
        func refreshFromStore() async {
            let stored = await store.work(id: workId)
            let storedChapters = await store.chapters(workId: workId)
            let storedPosition = await store.position(workId: workId)

            if position != storedPosition { position = storedPosition }
            if chapters != storedChapters { chapters = storedChapters }

            guard let stored else { return }

            if summary != stored.summary { summary = stored.summary }
            if tags != stored.tags { tags = stored.tags }

            isInLibrary = (stored.summary.libraryState ?? .none) != .none
        }

        /// Asks the service for the book again, behind whatever the store already put on screen.
        func reload() async {
            isLoading = true
            errorMessage = nil

            do {
                async let detailsTask = session.client.workDetails(id: workId)
                async let contentsTask = session.client.workContents(id: workId)
                let (loadedDetails, loadedChapters) = try await (detailsTask, contentsTask)

                details = loadedDetails
                await store.store(work: WorkSummary(loadedDetails), tags: loadedDetails.tags ?? [])
                await store.store(
                    chapters: loadedChapters.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) },
                    workId: workId
                )
                // Read back rather than painting what arrived: the service carries none of the progress
                // this device made, so its copy would empty the ring the moment it landed.
                await refreshFromStore()
            } catch let error as AuthorTodayError where error.requiresReauthentication {
                errorMessage = error.localizedDescription
            } catch {
                // A stored copy on screen beats an error message about refreshing it.
                if summary == nil { errorMessage = String(localized: "Couldn’t load this book.") }
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
