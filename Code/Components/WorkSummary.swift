//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import Foundation

/// One shape for the three sources of book rows — the library, the catalogue and a work's own details —
/// so a single row view serves every list.
struct WorkSummary: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let authorLine: String
    let coverURL: URL?
    let annotation: String?
    let seriesTitle: String?
    let seriesOrder: Int?

    let textLength: Int?
    let likeCount: Int?
    let isFinished: Bool?
    let status: WorkStatus?
    let adultOnly: Bool?
    let lastUpdateTime: Date?

    let readingProgress: Double?
    let hasStartedReading: Bool
    let lastReadTime: Date?
    let lastChapterId: Int?
    var libraryState: LibraryState?

    /// Where "read to the end" starts. The service's character offset rarely lands on the last one.
    static let readThreshold = 0.995

    /// The author is still adding chapters.
    var isOngoing: Bool { isFinished != true }

    /// The reader has been through it.
    var isReadToTheEnd: Bool { (readingProgress ?? 0) >= Self.readThreshold }

    var isPaid: Bool { status == .sales || status == .subscription }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
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
    static func length(_ characters: Int?) -> String? {
        guard let characters, characters > 0 else { return nil }

        let pages = max(1, characters / 1800)
        return String(localized: "\(pages) pp.")
    }

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
