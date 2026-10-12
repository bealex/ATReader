//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookRenderer
import BookStorage
import Foundation
import Testing

@testable import Bookhold

/// The library set before anyone opens it, so a book's first opening reads what its later ones do.
struct PreparingAheadTests {
    @Test
    func theChapterABookOpensOnIsSetFirst() async {
        let (store, database) = Self.store()

        defer { try? FileManager.default.removeItem(at: database) }

        await Self.keep(book: 1, chapters: [ 11, 12, 13 ], in: store)
        await Self.keep(book: 2, chapters: [ 21, 22 ], in: store)
        await store.store(position: ReadingPosition(workId: 1, chapterId: 13, characterOffset: 4, updatedAt: .now))

        #expect(await store.unpreparedChapters().map(\.chapterId) == [ 13, 11, 21, 12, 22 ])
    }

    @Test
    func catchingUpLeavesNothingToSet() async {
        let (store, database) = Self.store()

        defer { try? FileManager.default.removeItem(at: database) }

        await Self.keep(book: 1, chapters: [ 11, 12 ], in: store)
        await Self.keep(book: 2, chapters: [ 21 ], in: store)

        let processor = BookProcessor(store: store)

        await processor.catchUp().value

        #expect(await store.unpreparedChapters().isEmpty)
        #expect(await store.contentHash(workId: 2, chapterId: 21) != nil)
    }

    @Test
    func aChapterAlreadySetIsNotWaiting() async {
        let (store, database) = Self.store()

        defer { try? FileManager.default.removeItem(at: database) }

        await Self.keep(book: 1, chapters: [ 11, 12 ], in: store)
        _ = await BookProcessor(store: store).content(workId: 1, chapterId: 11)

        #expect(await store.unpreparedChapters() == [ ChapterPlace(workId: 1, chapterId: 12) ])
    }

    @Test
    func aBookOpensWhereItsReaderStopped() async {
        let (store, database) = Self.store()

        defer { try? FileManager.default.removeItem(at: database) }

        let contents = [ 11, 12, 13 ].enumerated().map { place, id in
            BookChapter(id: id, workId: 1, title: nil, sortOrder: place, textLength: 10)
        }

        #expect(await ChapterUpdateService.opening(of: 1, among: contents, in: store) == 11)

        await store.store(position: ReadingPosition(workId: 1, chapterId: 12, characterOffset: 0, updatedAt: .now))

        #expect(await ChapterUpdateService.opening(of: 1, among: contents, in: store) == 12)
    }

    private static func keep(book: Int, chapters: [Int], in store: SQLiteBookStore) async {
        await store.store(
            chapters: chapters.enumerated().map { place, id in
                BookChapter(id: id, workId: book, title: nil, sortOrder: place, textLength: 10)
            },
            workId: book
        )

        for id in chapters {
            await store.store(
                body: ChapterBody(id: id, title: nil, html: "<p>Lorem ipsum \(id)</p>", lastModificationTime: nil),
                workId: book
            )
        }
    }

    private static func store() -> (SQLiteBookStore, URL) {
        let database = FileManager.default.temporaryDirectory
            .appendingPathComponent("ahead-\(UUID().uuidString).sqlite")

        return (SQLiteBookStore(fileURL: database), database)
    }
}
