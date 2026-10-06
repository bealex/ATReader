//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import Foundation
import Testing

@testable import Bookhold

/// What two windows on one library may not do to each other through the store they share.
struct SeveralWindowsTests {
    @Test
    func takingOneBookOffTheShelvesLeavesTheRest() async {
        let (store, database) = Self.store()

        defer { try? FileManager.default.removeItem(at: database) }

        await store.replaceLibrary(with: [ Self.book(id: 1), Self.book(id: 2), Self.book(id: 3) ])
        await store.takeOffShelves(workId: 2)

        #expect(Set(await store.books().map(\.id)) == [ 1, 3 ])
    }

    @Test
    func chaptersAreNewOnlyToTheFirstSweepThatMeetsThem() async {
        let (store, database) = Self.store()

        defer { try? FileManager.default.removeItem(at: database) }

        _ = await store.takeIn(chapters: [ Self.chapter(id: 10) ], workId: 1)

        let grown = [ Self.chapter(id: 10), Self.chapter(id: 11) ]
        let first = await store.takeIn(chapters: grown, workId: 1)
        let second = await store.takeIn(chapters: grown, workId: 1)

        #expect(first == [ 11 ])
        #expect(second.isEmpty)
    }

    private static func store() -> (SQLiteBookStore, URL) {
        let database = FileManager.default.temporaryDirectory
            .appendingPathComponent("windows-\(UUID().uuidString).sqlite")

        return (SQLiteBookStore(fileURL: database), database)
    }

    private static func book(id: Int) -> Book {
        Book(id: id, title: "Lorem \(id)", authorLine: "Ipsum", coverURL: nil, annotation: nil, libraryState: .reading)
    }

    private static func chapter(id: Int) -> BookChapter {
        BookChapter(id: id, workId: 1, title: "Dolor \(id)", sortOrder: id, textLength: 100)
    }
}
