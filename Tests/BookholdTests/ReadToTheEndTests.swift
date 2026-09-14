//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import Foundation
import Testing

@testable import Bookhold

/// What counts as having read a book to its end, which is the last page or the reader's own word for it.
///
/// The books are generated: only how long each chapter is and where the reader stopped matter here.
struct ReadToTheEndTests {
    /// The reader stands on the last page of the last chapter, which is the head of that page rather
    /// than the foot of the chapter, and the book has been read whole.
    private static let lastPage = 900

    @Test
    func storingTheContentsAgainLeavesAFinishedBookFinished() async throws {
        let store = try Self.store()

        try await Self.read(to: Self.lastPage, of: [ 1000, 1000 ], in: store)
        await store.store(chapters: Self.chapters(of: [ 1000, 1000 ]), workId: 1)

        #expect(await store.book(id: 1)?.summary.isReadToTheEnd == true)
    }

    /// A chapter published past where the reader stopped is a book they haven't finished, and the
    /// bookmark goes back to saying how far along they are.
    @Test
    func aChapterPublishedPastTheReaderTakesTheBookOffTheEnd() async throws {
        let store = try Self.store()

        try await Self.read(to: Self.lastPage, of: [ 1000, 1000 ], in: store)
        await store.store(chapters: Self.chapters(of: [ 1000, 1000, 1000 ]), workId: 1)

        let summary = try #require(await store.book(id: 1)?.summary)

        #expect(!summary.isReadToTheEnd)
        #expect(ReadingMark(summary)?.kind == .reading)
    }

    /// Nothing short of the whole counts, however little is left: the last hundredth of a long book is
    /// a chapter of a short one.
    @Test
    func stoppingShortOfTheLastPageIsNotTheEnd() async throws {
        let store = try Self.store()

        try await Self.read(to: 500, of: [ 1000, 100_000 ], in: store, whole: false)

        let summary = try #require(await store.book(id: 1)?.summary)

        #expect(!summary.isReadToTheEnd)
        #expect(summary.readAt == nil, "a book nobody has finished was dated as read")
    }

    // MARK: - The shelf the reader filed it on

    /// Finished is the reader's word for being done, and it cannot hold while the author is still
    /// writing. The service takes that filing once and never revises it when a chapter lands.
    @Test
    func aBookStillBeingWrittenIsNeverFiledAsFinished() async throws {
        let store = try Self.store()

        await store.store(book: Self.book(isComplete: false, shelf: .finished))

        let summary = try #require(await store.book(id: 1)?.summary)

        #expect(summary.libraryState == .reading)
        #expect(!summary.isReadToTheEnd)
    }

    @Test
    func aBookItsAuthorHasFinishedKeepsThatShelf() async throws {
        let store = try Self.store()

        await store.store(book: Self.book(isComplete: true, shelf: .finished))

        #expect(await store.book(id: 1)?.summary.libraryState == .finished)
        #expect(await store.book(id: 1)?.summary.isReadToTheEnd == true)
    }

    /// A book the author went back to is one the reader has not finished after all.
    @Test
    func aChapterPublishedAfterwardsTakesTheBookOffFinished() async throws {
        let store = try Self.store()

        await store.store(book: Self.book(isComplete: true, shelf: .finished))
        await store.store(chapters: Self.chapters(of: [ 1000, 1000 ]), workId: 1)

        #expect(await store.book(id: 1)?.summary.libraryState == .finished, "stored twice, not published twice")

        await store.store(chapters: Self.chapters(of: [ 1000, 1000, 1000 ]), workId: 1)

        #expect(await store.book(id: 1)?.summary.libraryState == .reading)
    }

    /// Every chapter of a book is new the first time its contents are read, which says nothing about
    /// the author having written since.
    @Test
    func theFirstContentsOfABookLeaveItsShelfAlone() async throws {
        let store = try Self.store()

        await store.store(book: Self.book(isComplete: true, shelf: .finished))
        await store.store(chapters: Self.chapters(of: [ 1000, 1000 ]), workId: 1)

        #expect(await store.book(id: 1)?.summary.libraryState == .finished)
    }

    // MARK: - A book to read

    /// Puts a book of these chapter lengths in the store and stands the reader at `offset` in the last
    /// of them, reading it whole where the last page was reached.
    private static func read(
        to offset: Int,
        of lengths: [Int],
        in store: SQLiteBookStore,
        whole: Bool = true
    ) async throws {
        let chapters = chapters(of: lengths)
        let last = try #require(chapters.last)

        await store.replaceLibrary(with: [ book() ])
        await store.store(chapters: chapters, workId: 1)
        await store.store(
            position: .init(workId: 1, chapterId: last.id, characterOffset: offset, updatedAt: .now)
        )

        if whole { await store.store(progress: 1, workId: 1) }
    }

    private static func chapters(of lengths: [Int]) -> [BookChapter] {
        lengths.enumerated().map { index, length in
            BookChapter(
                id: index + 1,
                workId: 1,
                title: "Глава \(index + 1)",
                sortOrder: index,
                textLength: length
            )
        }
    }

    private static func book(isComplete: Bool = false, shelf: BookShelf = .reading) -> Book {
        Book(
            id: 1,
            title: "Книга",
            authorLine: "Автор",
            coverURL: nil,
            annotation: nil,
            isFinished: isComplete,
            libraryState: shelf
        )
    }

    private static func store() throws -> SQLiteBookStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        return SQLiteBookStore(fileURL: folder.appendingPathComponent("library.sqlite"))
    }
}
