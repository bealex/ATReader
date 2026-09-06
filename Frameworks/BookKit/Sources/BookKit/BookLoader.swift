//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// Whatever a book can be refreshed from. Two of these exist: the service, and a book already read
/// out of a file.
///
/// Every answer is optional rather than thrown. A book from a file has nothing upstream at all: its
/// text is on the device and nowhere else, and `nil` says exactly that. Callers read from the store
/// first anyway, so `nil` means "what you have is all there is" and needs no special case.
public protocol BookLoader: Sendable {
    /// True where this loader is the one behind the book.
    func handles(bookId: Int) -> Bool

    func book(id: Int) async throws -> Book?

    func contents(of bookId: Int) async throws -> [BookChapter]?

    func body(of chapterId: Int, in bookId: Int) async throws -> ChapterBody?

    /// Tells whatever is upstream where the reader got to.
    func report(
        _ position: ReadingPosition,
        chapterProgress: Double,
        bookProgress: Double,
        sessionId: String?
    ) async
}

extension BookLoader {
    public func report(
        _ position: ReadingPosition,
        chapterProgress: Double,
        bookProgress: Double,
        sessionId: String?
    ) async {}
}

/// The loaders in front of one library, asked in turn.
///
/// This is what removes the `isLocal` branch from every fetch: a book from a file routes to a loader
/// that answers `nil`, the store already holds its text, and there is nothing to tell apart.
public struct BookLoaders: BookLoader {
    private let loaders: [any BookLoader]

    public init(_ loaders: [any BookLoader]) {
        self.loaders = loaders
    }

    private func loader(for bookId: Int) -> (any BookLoader)? {
        loaders.first { $0.handles(bookId: bookId) }
    }

    public func handles(bookId: Int) -> Bool { loader(for: bookId) != nil }

    public func book(id: Int) async throws -> Book? {
        try await loader(for: id)?.book(id: id) ?? nil
    }

    public func contents(of bookId: Int) async throws -> [BookChapter]? {
        try await loader(for: bookId)?.contents(of: bookId) ?? nil
    }

    public func body(of chapterId: Int, in bookId: Int) async throws -> ChapterBody? {
        try await loader(for: bookId)?.body(of: chapterId, in: bookId) ?? nil
    }

    public func report(
        _ position: ReadingPosition,
        chapterProgress: Double,
        bookProgress: Double,
        sessionId: String?
    ) async {
        await loader(for: position.workId)?
            .report(position, chapterProgress: chapterProgress, bookProgress: bookProgress, sessionId: sessionId)
    }
}

/// A book already read out of a file. Everything it has went into the store on the way in, so there
/// is nothing here to fetch and nothing to refresh.
public struct FileBookLoader: BookLoader {
    public init() {}

    public func handles(bookId: Int) -> Bool { BookNumbering.isLocal(bookId) }

    public func book(id: Int) async throws -> Book? { nil }

    public func contents(of bookId: Int) async throws -> [BookChapter]? { nil }

    public func body(of chapterId: Int, in bookId: Int) async throws -> ChapterBody? { nil }
}
