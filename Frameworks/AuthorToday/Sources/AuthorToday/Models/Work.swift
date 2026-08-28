//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// The shape the service returns for a work everywhere except the catalogue: library entries,
/// `/v1/work/meta-info` and — extended with an annotation and tags — `/v1/work/{id}/details`.
public struct WorkMetaInfo: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let title: String
    public let coverUrl: String?

    public let authorId: Int?
    public let authorFIO: String?
    public let authorUserName: String?
    public let coAuthorFIO: String?

    public let seriesId: Int?
    public let seriesTitle: String?
    public let seriesOrder: Int?

    public let textLength: Int?
    public let textLengthLastRead: Int?
    public let isFinished: Bool?
    public let lastUpdateTime: Date?
    public let lastModificationTime: Date?

    public let lastReadTime: Date?
    public let lastChapterId: Int?
    public let lastChapterProgress: Double?

    public let likeCount: Int?
    public let commentCount: Int?
    public let price: Double?
    public let discount: Double?
    public let isPurchased: Bool?
    public let adultOnly: Bool?

    public let status: WorkStatus?
    public let workForm: WorkForm?
    public let format: WorkFormat?
    public let inLibraryState: LibraryState?
    public let addedToLibraryTime: Date?

    public var coverURL: URL? { CoverURL.absolute(coverUrl) }

    /// The author line as the site shows it, co-author included.
    public var authorLine: String {
        let names = [ authorFIO, coAuthorFIO ].compactMap { $0 }.filter { !$0.isEmpty }
        return names.isEmpty ? String(localized: "Unknown author", bundle: .module) : names.joined(separator: ", ")
    }

    /// How much of the published text the reader has already gone through, `0…1`.
    ///
    /// Only the character offset answers this. ``lastChapterProgress`` measures one chapter rather than
    /// the book, so it cannot stand in: a reader through chapter three of fifty would read as a reader
    /// through the book. A caller that wants a figure anyway derives it from a stored reading position
    /// and the chapter lengths, which is a question the service cannot answer.
    public var readingProgress: Double? {
        guard let textLengthLastRead, let textLength, textLength > 0 else { return nil }

        return min(1, max(0, Double(textLengthLastRead) / Double(textLength)))
    }

    /// How far into its current chapter the reader is, `0…1`.
    public var lastChapterFraction: Double? { Progress.fraction(lastChapterProgress) }

    public var hasStartedReading: Bool { lastChapterId != nil || (textLengthLastRead ?? 0) > 0 }

    /// The author's own progress: a finished work is complete, an ongoing one is still being written.
    public var isOngoing: Bool { isFinished != true }
}

/// `/v1/work/{id}/details` — a work plus the blurb, tags and series listing.
public struct WorkDetails: Decodable, Sendable, Identifiable {
    public let id: Int
    public let title: String
    public let coverUrl: String?
    public let annotation: String?
    public let authorNotes: String?
    public let tags: [String]?
    public let authorId: Int?
    public let authorFIO: String?
    public let authorUserName: String?
    public let coAuthorFIO: String?
    public let seriesId: Int?
    public let seriesTitle: String?
    public let textLength: Int?
    public let textLengthLastRead: Int?
    public let isFinished: Bool?
    public let likeCount: Int?
    public let commentCount: Int?
    public let reviewCount: Int?
    public let price: Double?
    public let isPurchased: Bool?
    public let adultOnly: Bool?
    public let lastUpdateTime: Date?
    public let lastChapterId: Int?
    public let lastChapterProgress: Double?
    public let status: WorkStatus?
    public let workForm: WorkForm?
    public let format: WorkFormat?
    public let inLibraryState: LibraryState?
    public let freeChapterCount: Int?

    public var coverURL: URL? { CoverURL.absolute(coverUrl) }

    public var authorLine: String {
        let names = [ authorFIO, coAuthorFIO ].compactMap { $0 }.filter { !$0.isEmpty }
        return names.isEmpty ? String(localized: "Unknown author", bundle: .module) : names.joined(separator: ", ")
    }

    /// How much of the published text the reader has already gone through, `0…1`. See
    /// ``WorkMetaInfo/readingProgress`` for why a chapter position cannot stand in for a missing offset.
    public var readingProgress: Double? {
        guard let textLengthLastRead, let textLength, textLength > 0 else { return nil }

        return min(1, max(0, Double(textLengthLastRead) / Double(textLength)))
    }

    /// How far into its current chapter the reader is, `0…1`.
    public var lastChapterFraction: Double? { Progress.fraction(lastChapterProgress) }
}

/// The service speaks progress as a percentage. Every reading of one goes through here, so the unit is
/// converted in one place rather than at each call site. See `Documentation/API.md`.
enum Progress {
    static func fraction(_ percentage: Double?) -> Double? {
        guard let percentage else { return nil }

        return min(1, max(0, percentage / 100))
    }

    static func percentage(_ fraction: Double) -> Double { min(100, max(0, fraction * 100)) }
}

/// One entry of a work's table of contents.
public struct ChapterInfo: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let workId: Int?
    public let title: String?
    public let isDraft: Bool?
    public let sortOrder: Int?
    public let publishTime: Date?
    public let lastModificationTime: Date?
    public let textLength: Int?
    public let isAvailable: Bool?

    public init(
        id: Int,
        workId: Int?,
        title: String?,
        isDraft: Bool? = nil,
        sortOrder: Int?,
        publishTime: Date? = nil,
        lastModificationTime: Date? = nil,
        textLength: Int?,
        isAvailable: Bool? = nil
    ) {
        self.id = id
        self.workId = workId
        self.title = title
        self.isDraft = isDraft
        self.sortOrder = sortOrder
        self.publishTime = publishTime
        self.lastModificationTime = lastModificationTime
        self.textLength = textLength
        self.isAvailable = isAvailable
    }

    /// Draft chapters are visible in the contents but carry no readable body.
    public var isReadable: Bool { isAvailable != false && isDraft != true }

    public var displayTitle: String {
        guard
            let title,
            !title.isEmpty
        else {
            return String(localized: "Chapter \((sortOrder ?? 0) + 1)", bundle: .module)
        }

        return title
    }
}

/// A chapter body, already decrypted into HTML by ``AuthorTodayClient``.
public struct ChapterText: Codable, Sendable, Identifiable {
    public let id: Int
    public let title: String?
    public let html: String
    public let lastModificationTime: Date?

    public init(id: Int, title: String?, html: String, lastModificationTime: Date?) {
        self.id = id
        self.title = title
        self.html = html
        self.lastModificationTime = lastModificationTime
    }
}

/// The raw, still-encrypted chapter payload.
struct EncryptedChapterText: Decodable, Sendable {
    let id: Int
    let title: String?
    let text: String
    let key: String
    let lastModificationTime: Date?
}

/// `/v1/reader/start/{workId}/{chapterId}` — where the reader left off, plus the contents.
public struct ReaderStats: Decodable, Sendable {
    public let workId: Int?
    public let chapterId: Int?
    public let chapterTitle: String?
    public let chapterProgress: Double?
    public let lastReadTime: Date?
    public let chapters: [ChapterInfo]?
    public let workInLibraryState: LibraryState?
    public let sessionId: String?
}

/// One position from `/v1/account/reading-progress`: where the service thinks a reader stopped.
public struct ReadingProgressInfo: Decodable, Sendable {
    public let workId: Int
    public let chapterId: Int?
    public let chapterProgress: Double?
    public let lastReadTime: Date?
}

/// A genre from `/v1/work/genres`.
public struct Genre: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let title: String
    public let parentId: Int?
    public let code: String?
    public let workCount: Int?

    /// Sub-genres carry a parent; the catalogue's own filter lists only the top level.
    public var isTopLevel: Bool { parentId == nil }
}

/// The ranking windows the charts offer, mirroring `/v1/catalog/rating-periods`.
public enum RatingPeriod: String, Sendable, CaseIterable, Hashable {
    case today
    case yesterday
    case week
    case month
    case year

    public var title: String {
        switch self {
            case .today: String(localized: "Today", bundle: .module)
            case .yesterday: String(localized: "Yesterday", bundle: .module)
            case .week: String(localized: "This week", bundle: .module)
            case .month: String(localized: "This month", bundle: .module)
            case .year: String(localized: "This year", bundle: .module)
        }
    }
}
