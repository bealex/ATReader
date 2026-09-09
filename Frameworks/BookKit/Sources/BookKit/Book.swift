//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// One book, whichever of the two places it came from.
///
/// Equality is every field, not the id. SwiftUI decides whether to redraw a row by comparing the values
/// its view holds, so a book that compares equal to its own newer self leaves the old ring, badges and
/// dates on screen for as long as the row lives.
public struct Book: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let title: String
    public let authorLine: String
    public let coverURL: URL?
    public let annotation: String?
    /// The series the book is filed under. The service's own, unless the reader has put the book in a
    /// series of their making, which outlives every refresh because it is kept in a table of its own.
    public var seriesTitle: String?
    public var seriesOrder: Int?
    /// Where the reader put this book in a series they arranged themselves.
    ///
    /// Kept apart from ``seriesOrder``, which is the volume the book states. Writing a place into that
    /// destroys what the book says about itself, and the two answer different questions: one is where
    /// the reader wants it, the other is which volume it is.
    public var shelfOrder: Int?

    public let textLength: Int?
    public let likeCount: Int?
    public let isFinished: Bool?
    public let status: BookPricing?
    public let isPurchased: Bool?
    public let adultOnly: Bool?
    public let lastUpdateTime: Date?

    public var readingProgress: Double?
    public let hasStartedReading: Bool
    public let lastReadTime: Date?
    public let lastChapterId: Int?
    public var libraryState: BookShelf?

    /// Where "read to the end" starts. The service's character offset rarely lands on the last one.
    public static let readThreshold = 0.995

    public init(
        id: Int,
        title: String,
        authorLine: String,
        coverURL: URL?,
        annotation: String?,
        seriesTitle: String? = nil,
        seriesOrder: Int? = nil,
        shelfOrder: Int? = nil,
        textLength: Int? = nil,
        likeCount: Int? = nil,
        isFinished: Bool? = nil,
        status: BookPricing? = nil,
        isPurchased: Bool? = nil,
        adultOnly: Bool? = nil,
        lastUpdateTime: Date? = nil,
        readingProgress: Double? = nil,
        hasStartedReading: Bool = false,
        lastReadTime: Date? = nil,
        lastChapterId: Int? = nil,
        libraryState: BookShelf? = nil
    ) {
        self.id = id
        self.title = title
        self.authorLine = authorLine
        self.coverURL = coverURL
        self.annotation = annotation
        self.seriesTitle = seriesTitle
        self.seriesOrder = seriesOrder
        self.shelfOrder = shelfOrder
        self.textLength = textLength
        self.likeCount = likeCount
        self.isFinished = isFinished
        self.status = status
        self.isPurchased = isPurchased
        self.adultOnly = adultOnly
        self.lastUpdateTime = lastUpdateTime
        self.readingProgress = readingProgress
        self.hasStartedReading = hasStartedReading
        self.lastReadTime = lastReadTime
        self.lastChapterId = lastChapterId
        self.libraryState = libraryState
    }

    /// The author is still adding chapters.
    public var isOngoing: Bool { isFinished != true }

    /// The author has written its last chapter.
    public var isComplete: Bool { isFinished == true }

    /// The reader has been through everything published so far.
    public var isReadToTheEnd: Bool { (readingProgress ?? 0) >= Self.readThreshold }

    /// Written to its end and read to its end. Only both together finish a book.
    public var isFinishedReading: Bool { isComplete && isReadToTheEnd }

    /// Read as far as the book goes, with the author still writing it.
    public var isCaughtUp: Bool { isOngoing && isReadToTheEnd }

    public var isPaid: Bool { status == .sales || status == .subscription }

    /// True where the book came from a file rather than the service.
    public var isLocal: Bool { BookNumbering.isLocal(id) }

    /// The series this book belongs to, where the service named one.
    public var series: String? {
        guard let seriesTitle, !seriesTitle.isEmpty else { return nil }

        return seriesTitle
    }

    /// Sold outright, and the service has said it isn't bought.
    ///
    /// Nothing less certain counts. A missing `isPurchased` is not a "no", and a subscription is read
    /// by subscribing rather than by buying, so neither earns a price marker: telling a reader to buy
    /// what they already own is worse than saying nothing.
    public var needsBuying: Bool { status == .sales && isPurchased == false }

    /// The same book under another name.
    ///
    /// For two copies of one book whose libraries titled it differently: the copy that is kept is
    /// chosen on other grounds, and can be the one whose title says the less of the two.
    public func titled(_ title: String) -> Self {
        Self(
            id: id,
            title: title,
            authorLine: authorLine,
            coverURL: coverURL,
            annotation: annotation,
            seriesTitle: seriesTitle,
            seriesOrder: seriesOrder,
            shelfOrder: shelfOrder,
            textLength: textLength,
            likeCount: likeCount,
            isFinished: isFinished,
            status: status,
            isPurchased: isPurchased,
            adultOnly: adultOnly,
            lastUpdateTime: lastUpdateTime,
            readingProgress: readingProgress,
            hasStartedReading: hasStartedReading,
            lastReadTime: lastReadTime,
            lastChapterId: lastChapterId,
            libraryState: libraryState
        )
    }

    /// Fills whatever this copy doesn't know from an older one.
    ///
    /// The shelf and a book's own details each carry what the other leaves out: the library has no
    /// blurb, and the details have no series order or last-read time. Whichever arrives second would
    /// otherwise erase what the first brought, which is what emptied every blurb on each launch.
    ///
    /// ``readingProgress`` is deliberately taken as it comes, absence included. The store keeps the
    /// figure this device derived in a column of its own and that is the one that counts; carrying a
    /// stale one forward here would put it beyond reach of ever being corrected.
    public func merged(over previous: Self) -> Self {
        Self(
            id: id,
            title: title,
            authorLine: authorLine,
            coverURL: coverURL ?? previous.coverURL,
            annotation: annotation ?? previous.annotation,
            seriesTitle: seriesTitle ?? previous.seriesTitle,
            seriesOrder: seriesOrder ?? previous.seriesOrder,
            shelfOrder: shelfOrder ?? previous.shelfOrder,
            textLength: textLength ?? previous.textLength,
            likeCount: likeCount ?? previous.likeCount,
            isFinished: isFinished ?? previous.isFinished,
            status: status ?? previous.status,
            isPurchased: isPurchased ?? previous.isPurchased,
            adultOnly: adultOnly ?? previous.adultOnly,
            lastUpdateTime: lastUpdateTime ?? previous.lastUpdateTime,
            readingProgress: readingProgress,
            hasStartedReading: hasStartedReading || previous.hasStartedReading,
            lastReadTime: lastReadTime ?? previous.lastReadTime,
            lastChapterId: lastChapterId ?? previous.lastChapterId,
            libraryState: libraryState ?? previous.libraryState
        )
    }
}

/// Which shelf of the reader's library a book sits on.
///
/// The raw values are the service's own, so a stored book decodes to the same case it always did and
/// the mapping in `AuthorTodayBooks` is total by construction.
public enum BookShelf: String, Codable, Hashable, Sendable, CaseIterable {
    case none = "None"
    case reading = "Reading"
    case saved = "Saved"
    case finished = "Finished"
    case disliked = "Disliked"

    /// The shelves worth offering as a filter — `none` means "not in the library at all".
    public static let shelves: [Self] = [ .reading, .saved, .finished ]
}

/// What it costs to read a book. Raw values are the service's, for the same reason as ``BookShelf``.
public enum BookPricing: String, Codable, Hashable, Sendable {
    case free = "Free"
    case subscription = "Subscription"
    case sales = "Sales"
    case suspended = "Suspended"
}
