//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import Foundation

/// One shape for the three sources of book rows — the library, the catalogue and a work's own details —
/// so a single row view serves every list.
///
/// Equality is every field, not the id. SwiftUI decides whether to redraw a row by comparing the values
/// its view holds, so a book that compares equal to its own newer self leaves the old ring, badges and
/// dates on screen for as long as the row lives.
struct WorkSummary: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let authorLine: String
    let coverURL: URL?
    let annotation: String?
    /// The series the book is filed under. The service's own, unless the reader has put the book in a
    /// series of their making, which outlives every refresh because it is kept in a table of its own.
    var seriesTitle: String?
    var seriesOrder: Int?

    let textLength: Int?
    let likeCount: Int?
    let isFinished: Bool?
    let status: WorkStatus?
    let isPurchased: Bool?
    let adultOnly: Bool?
    let lastUpdateTime: Date?

    var readingProgress: Double?
    let hasStartedReading: Bool
    let lastReadTime: Date?
    let lastChapterId: Int?
    var libraryState: LibraryState?

    /// Where "read to the end" starts. The service's character offset rarely lands on the last one.
    static let readThreshold = 0.995

    /// The author is still adding chapters.
    var isOngoing: Bool { isFinished != true }

    /// The author has written its last chapter.
    var isComplete: Bool { isFinished == true }

    /// The reader has been through everything published so far.
    var isReadToTheEnd: Bool { (readingProgress ?? 0) >= Self.readThreshold }

    /// Written to its end and read to its end. Only both together finish a book.
    var isFinishedReading: Bool { isComplete && isReadToTheEnd }

    /// Read as far as the book goes, with the author still writing it.
    var isCaughtUp: Bool { isOngoing && isReadToTheEnd }

    var isPaid: Bool { status == .sales || status == .subscription }

    /// The series this book belongs to, where the service named one.
    var series: String? {
        guard let seriesTitle, !seriesTitle.isEmpty else { return nil }

        return seriesTitle
    }

    /// Sold outright, and the service has said it isn't bought.
    ///
    /// Nothing less certain counts. A missing `isPurchased` is not a "no", and a subscription is read
    /// by subscribing rather than by buying, so neither earns a price marker: telling a reader to buy
    /// what they already own is worse than saying nothing.
    var needsBuying: Bool { status == .sales && isPurchased == false }

    /// Fills whatever this copy doesn't know from an older one.
    ///
    /// The shelf and a book's own details each carry what the other leaves out: the library has no
    /// blurb, and the details have no series order or last-read time. Whichever arrives second would
    /// otherwise erase what the first brought, which is what emptied every blurb on each launch.
    ///
    /// ``readingProgress`` is deliberately taken as it comes, absence included. `LocalStore` keeps the
    /// figure this device derived in a column of its own and that is the one that counts; carrying a
    /// stale one forward here would put it beyond reach of ever being corrected.
    func merged(over previous: Self) -> Self {
        Self(
            id: id,
            title: title,
            authorLine: authorLine,
            coverURL: coverURL ?? previous.coverURL,
            annotation: annotation ?? previous.annotation,
            seriesTitle: seriesTitle ?? previous.seriesTitle,
            seriesOrder: seriesOrder ?? previous.seriesOrder,
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

extension WorkSummary {
    init(_ work: WorkMetaInfo) {
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
            status: work.status,
            isPurchased: work.isPurchased,
            adultOnly: work.adultOnly,
            lastUpdateTime: work.lastUpdateTime ?? work.lastModificationTime,
            readingProgress: work.readingProgress,
            hasStartedReading: work.hasStartedReading,
            lastReadTime: work.lastReadTime,
            lastChapterId: work.lastChapterId,
            libraryState: work.inLibraryState
        )
    }

    init(_ work: CatalogWork) {
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
            status: work.status,
            isPurchased: work.isPurchased,
            adultOnly: work.adultOnly,
            lastUpdateTime: work.lastModificationTime,
            readingProgress: nil,
            hasStartedReading: false,
            lastReadTime: nil,
            lastChapterId: nil,
            libraryState: work.workInLibraryState
        )
    }

    init(_ work: WorkDetails) {
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
            status: work.status,
            isPurchased: work.isPurchased,
            adultOnly: work.adultOnly,
            lastUpdateTime: work.lastUpdateTime,
            readingProgress: work.readingProgress,
            hasStartedReading: work.lastChapterId != nil,
            lastReadTime: nil,
            lastChapterId: work.lastChapterId,
            libraryState: work.inLibraryState
        )
    }
}

/// Shared number and date wording, so every screen phrases a book's size the same way.
enum WorkFormatting {
    static func likes(_ count: Int?) -> String? {
        guard let count, count > 0 else { return nil }

        return count.formatted(.number.notation(.compactName))
    }

    static func progress(_ value: Double?) -> String? {
        guard let value, value > 0 else { return nil }

        return (value).formatted(.percent.precision(.fractionLength(0)))
    }

    static func updated(_ date: Date?) -> String? {
        guard let date else { return nil }

        return String(localized: "Updated \(date.formatted(.relative(presentation: .named)))")
    }
}
