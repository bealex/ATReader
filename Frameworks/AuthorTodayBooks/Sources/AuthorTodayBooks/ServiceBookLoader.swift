//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import BookKit

/// The books the service has, behind the loader every screen asks.
public struct ServiceBookLoader: BookLoader {
    private let client: AuthorTodayClient

    public init(client: AuthorTodayClient) {
        self.client = client
    }

    /// Everything the service counts up from one. A book from a file is numbered below zero and is
    /// somebody else's to answer for.
    public func handles(bookId: Int) -> Bool { !BookNumbering.isLocal(bookId) }

    public func book(id: Int) async throws -> Book? {
        Book(try await client.workDetails(id: id))
    }

    public func contents(of bookId: Int) async throws -> [BookChapter]? {
        try await client.workContents(id: bookId).map(BookChapter.init)
    }

    public func body(of chapterId: Int, in bookId: Int) async throws -> ChapterBody? {
        ChapterBody(try await client.chapterText(workId: bookId, chapterId: chapterId))
    }

    /// Sent and forgotten. The endpoint answers 200 and stores nothing, so where a reader got to lives
    /// on the device; see the note in Documentation/API.md. Nothing here waits on it or reads it back.
    public func report(
        _ position: ReadingPosition,
        chapterProgress: Double,
        bookProgress: Double,
        sessionId: String?
    ) async {
        try? await client.updateProgress(
            workId: position.workId,
            chapterId: position.chapterId,
            workProgress: bookProgress,
            chapterProgress: chapterProgress,
            sessionId: sessionId
        )
    }
}
