//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import BookKit

/// Turns the three shapes the service returns a work in into the one shape the app draws.
///
/// The service's own enums stay beside the decoder that meets them, and these switches map them over.
/// Both sets carry the same raw values, so a book stored under the old ones decodes unchanged; the
/// switches are here rather than `init(rawValue:)` so a member added on either side is a build error.
extension BookShelf {
    public init(_ state: LibraryState) {
        switch state {
            case .none: self = .none
            case .reading: self = .reading
            case .saved: self = .saved
            case .finished: self = .finished
            case .disliked: self = .disliked
        }
    }
}

extension BookPricing {
    public init(_ status: WorkStatus) {
        switch status {
            case .free: self = .free
            case .subscription: self = .subscription
            case .sales: self = .sales
            case .suspended: self = .suspended
        }
    }
}

extension BookChapter {
    public init(_ chapter: ChapterInfo) {
        self.init(
            id: chapter.id,
            workId: chapter.workId,
            title: chapter.title,
            isDraft: chapter.isDraft,
            sortOrder: chapter.sortOrder,
            publishTime: chapter.publishTime,
            lastModificationTime: chapter.lastModificationTime,
            textLength: chapter.textLength,
            isAvailable: chapter.isAvailable
        )
    }
}

extension Book {
    public init(_ work: WorkMetaInfo) {
        self.init(
            id: work.id,
            title: work.title,
            authorLine: work.authorLine,
            coverURL: work.coverURL,
            annotation: nil,
            seriesTitle: work.seriesTitle,
            seriesOrder: work.seriesOrder,
            textLength: work.textLength,
            likeCount: work.likeCount,
            isFinished: work.isFinished,
            status: work.status.map(BookPricing.init),
            isPurchased: work.isPurchased,
            adultOnly: work.adultOnly,
            lastUpdateTime: work.lastUpdateTime ?? work.lastModificationTime,
            readingProgress: work.readingProgress,
            hasStartedReading: work.hasStartedReading,
            lastReadTime: work.lastReadTime,
            lastChapterId: work.lastChapterId,
            libraryState: work.inLibraryState.map(BookShelf.init)
        )
    }

    public init(_ work: CatalogWork) {
        self.init(
            id: work.id,
            title: work.title,
            authorLine: work.authorLine,
            coverURL: work.coverURL,
            annotation: work.annotation,
            seriesTitle: work.seriesTitle,
            seriesOrder: nil,
            textLength: work.textLength,
            likeCount: work.likeCount,
            isFinished: work.isFinished,
            status: work.status.map(BookPricing.init),
            isPurchased: work.isPurchased,
            adultOnly: work.adultOnly,
            lastUpdateTime: work.lastModificationTime,
            readingProgress: nil,
            hasStartedReading: false,
            lastReadTime: nil,
            lastChapterId: nil,
            libraryState: work.workInLibraryState.map(BookShelf.init)
        )
    }

    public init(_ work: WorkDetails) {
        self.init(
            id: work.id,
            title: work.title,
            authorLine: work.authorLine,
            coverURL: work.coverURL,
            annotation: work.annotation,
            seriesTitle: work.seriesTitle,
            seriesOrder: nil,
            textLength: work.textLength,
            likeCount: work.likeCount,
            isFinished: work.isFinished,
            status: work.status.map(BookPricing.init),
            isPurchased: work.isPurchased,
            adultOnly: work.adultOnly,
            lastUpdateTime: work.lastUpdateTime,
            readingProgress: work.readingProgress,
            hasStartedReading: work.lastChapterId != nil,
            lastReadTime: nil,
            lastChapterId: work.lastChapterId,
            libraryState: work.inLibraryState.map(BookShelf.init)
        )
    }
}

extension ChapterBody {
    /// The service's chapter, already decrypted by the client. From here on nothing can tell it from a
    /// chapter read out of a file.
    public init(_ text: ChapterText) {
        self.init(id: text.id, title: text.title, html: text.html, lastModificationTime: text.lastModificationTime)
    }
}
