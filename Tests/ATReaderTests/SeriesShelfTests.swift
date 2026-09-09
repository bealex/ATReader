//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import Foundation
import Testing

@testable import ATReader

/// What a series card puts on its shelf, and which of the two ways it stands.
///
/// Every book is there in both modes. What changes is how much room a book the reader is done with
/// takes: a cover while every cover is shown, a spine while it isn't.
@MainActor
struct SeriesShelfTests {
    private typealias Model = LibraryScreen.Model

    @Test
    func acardOpensOnWhatIsLeftToRead() {
        let model = Self.model()

        #expect(!model.showsEveryCover("Зимпель"))
    }

    @Test
    func tappingTheTitleSwitchesBetweenTheTwoWays() {
        let model = Self.model()

        model.toggleCovers(of: "Зимпель")
        #expect(model.showsEveryCover("Зимпель"))

        model.toggleCovers(of: "Зимпель")
        #expect(!model.showsEveryCover("Зимпель"))
    }

    /// One card at a time: opening one series' covers leaves the others as they were.
    @Test
    func eachSeriesKeepsItsOwnWay() {
        let model = Self.model()

        model.toggleCovers(of: "Зимпель")
        #expect(!model.showsEveryCover("Ворбат"))
    }

    /// A book behind the reader stands as a spine, and one they haven't finished as a cover.
    @Test
    func abookAlreadyReadStandsAsASpine() {
        let works = [ Self.book(id: 1, read: 1), Self.book(id: 2, read: 0.3) ]
        let group = Model.Group(id: "series:Зимпель", series: "Зимпель", works: works, updated: .now)
        let slots = Self.model().slots(of: group)

        #expect(slots.map(Self.isRead) == [ true, false ])
    }

    /// A volume between two the reader holds that they don't keeps its place on the shelf.
    @Test
    func avolumeTheReaderDoesNotHoldKeepsItsPlace() {
        let works = [ Self.book(id: 1, title: "Зимпель (Зимпель-1)"), Self.book(id: 3, title: "Зимпель (Зимпель-3)") ]
        let group = Model.Group(
            id: "series:Зимпель",
            series: "Зимпель",
            works: works,
            updated: .now,
            numbering: SeriesNumbering.read(works)
        )
        let slots = Self.model().slots(of: group)

        #expect(slots.contains { if case .missing(2) = $0 { true } else { false } })
    }

    /// A label the service files books under is not a series unless one writer wrote them.
    ///
    /// "LitRPG" is a shelf in a shop rather than a run of books, and three writers' books under it are
    /// three different things. What the reader put together themselves is theirs, whoever wrote it.
    @Test
    func alabelSharedBySeveralWritersIsNotOneSeries() async {
        let model = await Self.shelf(holding: [
            Self.book(id: 1, title: "Первая", author: "Первый Автор"),
            Self.book(id: 2, title: "Вторая", author: "Второй Автор"),
        ])

        #expect(model.groups.allSatisfy { $0.series == nil })
    }

    @Test
    func onewritersBooksUnderOneLabelAreASeries() async {
        let model = await Self.shelf(holding: [
            Self.book(id: 1, title: "Первая", author: "Имя Фамилия"),
            Self.book(id: 2, title: "Вторая", author: "Имя Фамилия"),
        ])

        #expect(model.groups.count == 1)
        #expect(model.groups.first?.series == "Зимпель")
    }

    /// Runs by different writers, held together by hand, stand on a card of their own headed by all
    /// of them. Filed under whichever of them wrote the most of it, the series would sit among that
    /// writer's own books as though the others had no part in it.
    @Test
    func acombinedSeriesStandsOnACardOfItsOwn() async throws {
        let database = FileManager.default.temporaryDirectory
            .appendingPathComponent("merge-\(UUID().uuidString).sqlite")
        let store = SQLiteBookStore(fileURL: database)
        let model = Model(session: SessionStore(), store: store)

        defer { try? FileManager.default.removeItem(at: database) }

        let held = [
            Self.book(id: 1, title: "Первая", author: "Первый Автор"),
            Self.book(id: 2, title: "Вторая", author: "Первый Автор"),
            Self.book(id: 3, title: "Третья", author: "Второй Автор"),
            Self.book(id: 4, title: "Четвёртая", author: "Второй Автор"),
        ]

        await store.store(books: held)
        await model.refreshFromStore()
        model.filter = .everything
        // Picked in a stated order, since the card is headed with its writers in the order they were
        // put together rather than in whatever order the shelf happened to list them.
        let first = try #require(model.allSeries.first { $0.author == "Первый Автор" })
        let second = try #require(model.allSeries.first { $0.author == "Второй Автор" })

        await model.merge([ first, second ], named: "Вместе")

        let shelf = model.shelves.first { $0.runs.contains { $0.series == "Вместе" } }

        #expect(model.shelves.count == 1)
        #expect(shelf?.name == "Первый Автор, Второй Автор")
    }

    /// Two spellings of one writer's name, held together, make one card under the name picked.
    @Test
    func mergedAuthorsStandOnOneCard() async {
        let database = FileManager.default.temporaryDirectory
            .appendingPathComponent("authors-\(UUID().uuidString).sqlite")
        let store = SQLiteBookStore(fileURL: database)
        let model = Model(session: SessionStore(), store: store)

        defer { try? FileManager.default.removeItem(at: database) }

        await store.store(books: [
            Self.book(id: 1, title: "Первая", author: "Имя Фамилия"),
            Self.book(id: 2, title: "Вторая", author: "Имя Отчество Фамилия"),
        ])
        await model.refreshFromStore()
        model.filter = .everything

        #expect(model.shelves.count == 2)

        await model.mergeAuthors([ "Имя Фамилия", "Имя Отчество Фамилия" ], as: "Имя Фамилия")

        #expect(model.shelves.count == 1)
        #expect(model.shelves.first?.name == "Имя Фамилия")
    }

    /// Two runs held together stand in the order their titles state, not one run after the other.
    ///
    /// Each run is ordered rightly on its own, and laying them end to end leaves volume four standing
    /// after volume one. Nobody arranged that, so what the titles say wins.
    @Test
    func acombinedSeriesStandsInVolumeOrder() async throws {
        let database = FileManager.default.temporaryDirectory
            .appendingPathComponent("order-\(UUID().uuidString).sqlite")
        let store = SQLiteBookStore(fileURL: database)
        let model = Model(session: SessionStore(), store: store)

        defer { try? FileManager.default.removeItem(at: database) }

        await store.store(books: [
            Self.book(id: 1, title: "Зимпель 4. Четвёртая", author: "Первый Автор"),
            Self.book(id: 2, title: "Зимпель 1. Первая", author: "Первый Автор"),
            Self.book(id: 3, title: "Зимпель 3. Третья", author: "Второй Автор"),
            Self.book(id: 4, title: "Зимпель 2. Вторая", author: "Второй Автор"),
        ])
        await model.refreshFromStore()
        model.filter = .everything

        let first = try #require(model.allSeries.first { $0.author == "Первый Автор" })
        let second = try #require(model.allSeries.first { $0.author == "Второй Автор" })

        await model.merge([ first, second ], named: "Зимпель")

        let run = try #require(model.shelves.first?.runs.first)

        #expect(run.numbering?.books.map(\.number) == [ 4, 3, 2, 1 ])
    }

    /// A shelf reading from a store of its own, holding just these books.
    private static func shelf(holding held: [Book]) async -> Model {
        let database = FileManager.default.temporaryDirectory
            .appendingPathComponent("label-\(UUID().uuidString).sqlite")
        let store = SQLiteBookStore(fileURL: database)
        let model = Model(session: SessionStore(), store: store)

        await store.store(books: held)
        await model.refreshFromStore()
        model.filter = .everything
        return model
    }

    private static func isRead(_ slot: SeriesSlot) -> Bool {
        guard case let .book(_, _, _, isRead) = slot else { return false }

        return isRead
    }

    private static func model() -> Model { Model(session: SessionStore()) }

    private static func book(
        id: Int,
        title: String = "Зимпель",
        read: Double = 0,
        author: String = "Имя Фамилия"
    ) -> Book {
        Book(
            id: id,
            title: title,
            authorLine: author,
            coverURL: nil,
            annotation: nil,
            seriesTitle: "Зимпель",
            seriesOrder: nil,
            textLength: 1000,
            likeCount: nil,
            isFinished: true,
            status: nil,
            isPurchased: nil,
            adultOnly: nil,
            lastUpdateTime: .now,
            readingProgress: read,
            hasStartedReading: read > 0,
            lastReadTime: nil,
            lastChapterId: nil,
            libraryState: .reading
        )
    }
}
