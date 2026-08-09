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
        /// Where to land after a chapter loads: the top for a forward move, the end for a backward one.
        enum PageAnchor {
            case first
            case last
        }

        let workId: Int
        let workTitle: String

        private(set) var chapters: [ChapterInfo] = []
        private(set) var currentChapterId: Int?
        private(set) var paragraphs: [ChapterHTML.Paragraph] = []
        private(set) var chapterTitle: String?
        private(set) var isLoading = false
        private(set) var errorMessage: String?

        /// The chapter laid out for the current style, and the range each page covers.
        private(set) var attributedText = NSAttributedString()
        private(set) var pageRanges: [NSRange] = []

        /// Bumped whenever the text is replaced, so the view knows to re-paginate. A chapter id alone
        /// is not enough — a cached chapter is swapped for the fresh one under the same id.
        private(set) var layoutRevision = 0

        var currentPage = 0 {
            didSet {
                guard currentPage != oldValue else { return }

                reportProgress()
            }
        }

        /// True when the chapter on screen came from disk and the network never answered.
        private(set) var isOffline = false

        @ObservationIgnored
        private let session: SessionStore

        @ObservationIgnored
        private let cache: BookCache

        @ObservationIgnored
        private var sessionId: String?

        @ObservationIgnored
        private var requestedChapterId: Int?

        @ObservationIgnored
        private var hasLoaded = false

        @ObservationIgnored
        private var lastReportedProgress: Double = -1

        @ObservationIgnored
        private var parsed: [Int: [ChapterHTML.Paragraph]] = [:]

        @ObservationIgnored
        private var pendingAnchor: PageAnchor = .first

        @ObservationIgnored
        private var lastStyle: ChapterTextStyle?

        @ObservationIgnored
        private var lastTextSize: CGSize = .zero

        init(
            workId: Int,
            workTitle: String,
            initialChapterId: Int?,
            session: SessionStore,
            cache: BookCache = .shared
        ) {
            self.workId = workId
            self.workTitle = workTitle
            self.requestedChapterId = initialChapterId
            self.session = session
            self.cache = cache
        }

        var readableChapters: [ChapterInfo] { chapters.filter(\.isReadable) }

        var pageCount: Int { pageRanges.count }

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

        /// The footer caption: where the reader is in the chapter, and the chapter in the book.
        var pageCaption: String? {
            guard pageCount > 0 else { return nil }
            guard
                let index = currentIndex
            else {
                return String(localized: "Page \(currentPage + 1) of \(pageCount)")
            }

            return String(
                localized: "Chapter \(index + 1)/\(readableChapters.count) · page \(currentPage + 1)/\(pageCount)"
            )
        }

        // MARK: - Layout

        /// Re-lays the chapter whenever the style or the page size changes, keeping the reader's place.
        ///
        /// The position is remembered as a character offset rather than a page number, because a bigger
        /// font means the same text spans more pages.
        func layout(style: ChapterTextStyle, textSize: CGSize) {
            guard !paragraphs.isEmpty, textSize.width > 1, textSize.height > 1 else { return }
            guard style != lastStyle || textSize != lastTextSize || pageRanges.isEmpty else { return }

            let anchor = pendingAnchor
            let anchorLocation = pageRanges.indices.contains(currentPage) ? pageRanges[currentPage].location : 0

            lastStyle = style
            lastTextSize = textSize
            attributedText = ChapterPagination.attributedText(for: paragraphs, style: style)
            pageRanges = ChapterPagination.pageRanges(in: attributedText, size: textSize)
            pendingAnchor = .first

            switch anchor {
                case .last:
                    currentPage = max(0, pageCount - 1)
                case .first where anchorLocation > 0:
                    currentPage = pageRanges.firstIndex { NSLocationInRange(anchorLocation, $0) } ?? 0
                case .first:
                    currentPage = 0
            }

            reportProgress()
        }

        // MARK: - Loading

        func loadIfNeeded() async {
            guard !hasLoaded else { return }

            hasLoaded = true
            isLoading = true
            errorMessage = nil

            // Opening a book counts as seeing whatever the daily sweep flagged for it.
            await UpdateBadge.clear(workId: workId)

            let contents: [ChapterInfo]?

            if let fetched = try? await session.client.workContents(id: workId) {
                contents = fetched
                await cache.store(contents: fetched, workId: workId)
            } else {
                contents = await cache.contents(workId: workId)
                isOffline = contents != nil
            }

            guard
                let contents
            else {
                errorMessage = String(localized: "Couldn’t open this book.")
                isLoading = false
                return
            }

            chapters = contents.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }

            let target =
                requestedChapterId.flatMap { candidate in
                    readableChapters.first { $0.id == candidate }?.id
                } ?? readableChapters.first?.id

            guard
                let target
            else {
                errorMessage = String(localized: "This book has no chapters you can read yet.")
                isLoading = false
                return
            }

            await startSession(chapterId: target)
            await open(chapterId: target)

            isLoading = false
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

        func open(chapterId: Int, anchor: PageAnchor = .first) async {
            guard currentChapterId != chapterId || paragraphs.isEmpty else { return }

            isLoading = true
            errorMessage = nil
            currentChapterId = chapterId
            lastReportedProgress = -1
            pendingAnchor = anchor
            chapterTitle = chapters.first { $0.id == chapterId }?.displayTitle

            if let alreadyParsed = parsed[chapterId] {
                apply(paragraphs: alreadyParsed)
                isLoading = false
                return
            }

            // Show the stored copy straight away, then let the network confirm or replace it.
            if let stored = await cache.chapter(workId: workId, chapterId: chapterId) {
                apply(paragraphs: stored.paragraphs, title: stored.title)
                isLoading = false
            }

            do {
                let chapter = try await session.client.chapterText(workId: workId, chapterId: chapterId)
                await cache.store(chapter: chapter, workId: workId)
                parsed[chapterId] = chapter.paragraphs
                apply(paragraphs: chapter.paragraphs, title: chapter.title)
                isOffline = false
            } catch let error as AuthorTodayError {
                // A cached copy on screen beats an error message about refreshing it.
                if paragraphs.isEmpty { errorMessage = error.localizedDescription } else { isOffline = true }
            } catch {
                if paragraphs.isEmpty {
                    errorMessage = String(localized: "Couldn’t load this chapter.")
                } else {
                    isOffline = true
                }
            }

            isLoading = false
        }

        /// Swapping the text invalidates the layout; the view re-runs ``layout(style:textSize:)`` next pass.
        private func apply(paragraphs: [ChapterHTML.Paragraph], title: String? = nil) {
            self.paragraphs = paragraphs
            pageRanges = []
            lastStyle = nil
            layoutRevision += 1

            if let title, !title.isEmpty { chapterTitle = title }
        }

        // MARK: - Moving through the book

        func goToPreviousChapter() async {
            guard let previous = previousChapter else { return }

            await open(chapterId: previous.id, anchor: .last)
        }

        func goToNextChapter() async {
            guard let next = nextChapter else { return }

            await open(chapterId: next.id, anchor: .first)
        }

        // MARK: - Progress

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
