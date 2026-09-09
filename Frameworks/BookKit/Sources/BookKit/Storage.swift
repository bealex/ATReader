//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// A chapter body as HTML, whichever side it came from.
///
/// The service's cipher is gone by the time one of these exists, and a book read out of a file writes
/// its sections as the same markup on purpose, so nothing downstream can tell the two apart.
public struct ChapterBody: Codable, Sendable, Identifiable {
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

/// Where a reader stopped in a book, as a character offset so it survives a change of font.
public struct ReadingPosition: Sendable, Equatable {
    public let workId: Int
    public let chapterId: Int
    public let characterOffset: Int
    public let updatedAt: Date

    public init(workId: Int, chapterId: Int, characterOffset: Int, updatedAt: Date) {
        self.workId = workId
        self.chapterId = chapterId
        self.characterOffset = characterOffset
        self.updatedAt = updatedAt
    }
}

/// A book as this device knows it: what the lists draw, plus the tags the book page shows.
public struct StoredBook: Sendable {
    public let summary: Book
    public let tags: [String]

    public init(summary: Book, tags: [String]) {
        self.summary = summary
        self.tags = tags
    }
}

/// Where one chapter sat when the book was last measured at a given setting.
public struct ChapterPlacement: Sendable, Equatable {
    public let startOffset: Double
    public let pageCount: Int
    /// Where the chapter after this one begins, so a run of cached chapters can carry on without
    /// laying any of them out.
    public let nextOffset: Double

    public init(startOffset: Double, pageCount: Int, nextOffset: Double) {
        self.startOffset = startOffset
        self.pageCount = pageCount
        self.nextOffset = nextOffset
    }
}

/// A chapter's text, parsed and ready to lay out.
public struct ChapterContent: Codable, Sendable {
    public var paragraphs: [Paragraph]
    /// The same paragraphs with every break point the language's dictionary allows already marked.
    /// Justified setting uses these; working them out costs about as much as laying the chapter out,
    /// so it happens once rather than on every re-pagination.
    public var hyphenated: [Paragraph]
    /// The language the chapter is written in, which decides which hyphenation dictionary lays it out
    /// and how it is shaped.
    public var language: String?
    /// The notes the text points at, by the id its markers carry.
    public var notes: [String: BookNote] = [:]

    public init(paragraphs: [Paragraph], hyphenated: [Paragraph], language: String?, notes: [String: BookNote] = [:]) {
        self.paragraphs = paragraphs
        self.hyphenated = hyphenated
        self.language = language
        self.notes = notes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        paragraphs = try container.decode([ Paragraph ].self, forKey: .paragraphs)
        hyphenated = try container.decode([ Paragraph ].self, forKey: .hyphenated)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        // A chapter prepared before notes were read carries none, and is still good text.
        notes = try container.decodeIfPresent([ String: BookNote ].self, forKey: .notes) ?? [:]
    }

    public var isEmpty: Bool { paragraphs.isEmpty }

    /// Every picture the chapter points at, in the order it stands in the text.
    public var imageSources: [String] { paragraphs.compactMap(\.imageSource) }
}

/// Where a book on the device came from.
///
/// A library with two ways in needs to say which one a book came by: a book the reader picked is theirs
/// to keep however the service feels about it, and a book from a service can be fetched again.
public enum BookSource: String, Sendable, Codable, CaseIterable {
    /// Picked out of the files on the device by the reader.
    case file
    case litres

    public var isService: Bool { self != .file }
}

/// What the device knows about a book it holds: where it came from, when, and what it was.
///
/// The two hashes are what stop the same book arriving twice. They answer different questions: the
/// archive says "this very download", and the content says "this book, whatever it arrived in", so a
/// book bought once and picked up again as a file is recognised as the one already here.
public struct LocalBookRecord: Sendable, Equatable {
    public let workId: Int
    /// What the book is filed under, which is what gives it its number.
    public let fingerprint: String
    public let importedAt: Date
    public let source: BookSource
    /// What the source calls it. A Litres art id; nothing for a book off a file.
    public let sourceId: String?
    /// When the source last changed it, which is what says the copy here is behind.
    public let sourceUpdatedAt: Date?
    /// The book's own text, hashed: the FB2 itself, not whatever carried it.
    public let contentHash: String?
    /// The container as it arrived, hashed. Nothing where the book arrived as plain text.
    public let archiveHash: String?

    public init(
        workId: Int,
        fingerprint: String,
        importedAt: Date = .now,
        source: BookSource = .file,
        sourceId: String? = nil,
        sourceUpdatedAt: Date? = nil,
        contentHash: String? = nil,
        archiveHash: String? = nil
    ) {
        self.workId = workId
        self.fingerprint = fingerprint
        self.importedAt = importedAt
        self.source = source
        self.sourceId = sourceId
        self.sourceUpdatedAt = sourceUpdatedAt
        self.contentHash = contentHash
        self.archiveHash = archiveHash
    }

    /// True where the source has moved on since this copy was taken.
    ///
    /// A source that says nothing about when it last changed cannot be behind: without a date there is
    /// nothing to compare, and fetching every book again on every run is worse than missing an edit.
    public func isBehind(_ updated: Date?) -> Bool {
        guard let updated else { return false }
        guard let sourceUpdatedAt else { return true }

        return updated > sourceUpdatedAt
    }
}

/// A chapter's text after the typesetter has been through it, and the hashes that say whether it is
/// still the text the reader was given.
public struct PreparedChapter: Sendable {
    public let chapterId: Int
    /// The chapter's own source text, hashed.
    public let contentHash: String
    /// This chapter's hash folded into every chapter before it. Equal chains mean equal books up to
    /// this point, which is what makes a re-run pick up where the last one stopped.
    public let chainHash: String
    public let content: ChapterContent

    public init(chapterId: Int, contentHash: String, chainHash: String, content: ChapterContent) {
        self.chapterId = chapterId
        self.contentHash = contentHash
        self.chainHash = chainHash
        self.content = content
    }
}
