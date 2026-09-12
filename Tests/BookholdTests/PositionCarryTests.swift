//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import Foundation
import Testing

@testable import Bookhold

/// Reading a file again may cut it into different pieces, and the reader's place has to survive that.
///
/// A position is kept against a chapter's id, and those are made from a chapter's place in the book:
/// cut the book differently and the old id names a different piece.
@MainActor
struct PositionCarryTests {
    private func store() -> SQLiteBookStore {
        SQLiteBookStore(
            fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("carry-\(UUID().uuidString).sqlite")
        )
    }

    /// Two books of the same file, cut differently. The same bytes, so both install over one another.
    private func book(_ pieces: [(String?, Int)]) -> ParsedBook {
        ParsedBook(
            title: "Проба",
            authors: [ "Автор" ],
            annotation: nil,
            language: "ru",
            series: nil,
            seriesOrder: nil,
            cover: nil,
            images: [:],
            sections: pieces.map { title, length in
                ParsedBook.Section(
                    title: title,
                    html: "<p>" + String(repeating: "я", count: length) + "</p>",
                    textLength: length
                )
            },
            identifier: "carry-test"
        )
    }

    @Test
    func keepsTheReadersPlaceWhenTheBookIsCutAgain() async throws {
        let store = store()
        let source = Data("one file".utf8)
        let whole = await BookInstaller.install(book([ (nil, 900) ]), source: source, store: store)
        let chapters = await store.chapters(workId: whole.id)

        // Two thirds of the way through the one chapter it had.
        let opened = try #require(chapters.first)

        await store.store(
            position: .init(workId: whole.id, chapterId: opened.id, characterOffset: 600, updatedAt: .now)
        )

        // The same file, read again and cut into three.
        await BookInstaller.install(book([ (nil, 300), ("Вторая", 300), ("Третья", 300) ]), source: source, store: store)

        let cut = await store.chapters(workId: whole.id)
        let moved = try #require(await store.position(workId: whole.id))

        #expect(cut.count == 3)
        // Character 600 of the book is the first character of the third piece.
        #expect(moved.chapterId == cut[2].id)
        #expect(moved.characterOffset == 0)
    }

    /// A place past everything the book now holds sits at the end of it rather than nowhere.
    @Test
    func putsAPlacePastTheEndInTheLastPiece() async throws {
        let store = store()
        let source = Data("another file".utf8)
        let whole = await BookInstaller.install(book([ (nil, 900) ]), source: source, store: store)
        let chapters = await store.chapters(workId: whole.id)

        let opened = try #require(chapters.first)

        await store.store(
            position: .init(workId: whole.id, chapterId: opened.id, characterOffset: 880, updatedAt: .now)
        )

        await BookInstaller.install(book([ (nil, 100), ("Вторая", 100) ]), source: source, store: store)

        let cut = await store.chapters(workId: whole.id)
        let moved = try #require(await store.position(workId: whole.id))

        let ending = try #require(cut.last)

        #expect(moved.chapterId == ending.id)
        #expect(moved.characterOffset == 100)
    }
}
