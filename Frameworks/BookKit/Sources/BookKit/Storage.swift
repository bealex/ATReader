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

    public init(paragraphs: [Paragraph], hyphenated: [Paragraph], language: String?) {
        self.paragraphs = paragraphs
        self.hyphenated = hyphenated
        self.language = language
    }

    public var isEmpty: Bool { paragraphs.isEmpty }

    /// Every picture the chapter points at, in the order it stands in the text.
    public var imageSources: [String] { paragraphs.compactMap(\.imageSource) }
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
