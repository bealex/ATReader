//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import Foundation
import Testing

@testable import Bookhold

/// The order the author cards stand in, which each filter answers differently: All books is a list to
/// look a writer up in, Reading is one to carry on from.
///
/// The writers here are written for the test.
@MainActor
struct ShelfOrderTests {
    private typealias Model = LibraryScreen.Model

    private static let writers = [ 1: "Авдей Абрикос", 2: "Мирон Маслов", 3: "Ярослав Ясень" ]

    /// All books stands by name, whenever anything of the writer's last changed.
    @Test
    func standsAllBooksByAuthorName() async {
        let model = await Self.shelf(updated: [ 3: .now, 1: .now.addingTimeInterval(-86400) ])

        model.filter = .everything

        #expect(model.shelves.map(\.name) == [ "Авдей Абрикос", "Мирон Маслов", "Ярослав Ясень" ])
    }

    /// Reading stands by what the service last changed, so the writer whose book grew a chapter is at
    /// the top.
    @Test
    func standsReadingByWhatChangedLast() async {
        let model = await Self.shelf(updated: [
            1: .now.addingTimeInterval(-3600),
            2: .now,
            3: .now.addingTimeInterval(-86400),
        ])

        model.filter = .reading

        #expect(model.shelves.map(\.name) == [ "Мирон Маслов", "Авдей Абрикос", "Ярослав Ясень" ])
    }

    /// A writer the service gives no date for stands after the ones it does, rather than among them.
    @Test
    func standsAWriterWithNoDateAfterTheRest() async {
        let model = await Self.shelf(updated: [ 1: .now.addingTimeInterval(-86400), 2: .now ])

        model.filter = .reading

        #expect(model.shelves.map(\.name) == [ "Мирон Маслов", "Авдей Абрикос", "Ярослав Ясень" ])
    }

    /// Reading a book is no change to it, so the shelf holds still under the reader.
    @Test
    func leavesReadingWhereItStandsWhenABookIsRead() async {
        let model = await Self.shelf(
            updated: [ 1: .now.addingTimeInterval(-3600), 2: .now, 3: .now.addingTimeInterval(-86400) ],
            read: [ 3: .now ]
        )

        model.filter = .reading

        #expect(model.shelves.map(\.name) == [ "Мирон Маслов", "Авдей Абрикос", "Ярослав Ясень" ])
    }

    /// A shelf of one book a writer, reading from a store of its own, with each of the named books last
    /// changed at the time given and the rest carrying no date at all.
    private static func shelf(updated: [Int: Date], read: [Int: Date] = [:]) async -> Model {
        let database = FileManager.default.temporaryDirectory
            .appendingPathComponent("order-\(UUID().uuidString).sqlite")
        let store = SQLiteBookStore(fileURL: database)
        let model = Model(session: SessionStore(), store: store)

        await store.store(books: writers.keys.sorted().map { book(id: $0, updated: updated[$0]) })

        for (workId, at) in read {
            await store.store(position: .init(workId: workId, chapterId: workId, characterOffset: 1, updatedAt: at))
        }

        await model.refreshFromStore()
        return model
    }

    private static func book(id: Int, updated: Date?) -> Book {
        Book(
            id: id,
            title: "Зимпель \(id)",
            authorLine: writers[id] ?? "",
            coverURL: nil,
            annotation: nil,
            seriesTitle: nil,
            seriesOrder: nil,
            textLength: 1000,
            likeCount: nil,
            isFinished: true,
            status: nil,
            isPurchased: nil,
            adultOnly: nil,
            lastUpdateTime: updated,
            readingProgress: 0.5,
            hasStartedReading: true,
            lastReadTime: nil,
            lastChapterId: nil,
            libraryState: .reading
        )
    }
}
