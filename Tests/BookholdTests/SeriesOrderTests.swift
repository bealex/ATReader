//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import Foundation
import Testing

@testable import Bookhold

/// Where a book's volume number comes from, and what it may not be.
///
/// A series counts from one, so nought is not a place in one. It reached the shelf as a place counted
/// from zero and was drawn as a volume, which put a book nought at the head of every series the reader
/// assembled and moved every volume after it down by one.
@MainActor
struct SeriesOrderTests {
    private typealias Model = LibraryScreen.Model

    @Test
    func filingASeriesSaysNothingAboutItsOrder() async {
        let database = FileManager.default.temporaryDirectory
            .appendingPathComponent("series-\(UUID().uuidString).sqlite")
        let store = SQLiteBookStore(fileURL: database)

        defer { try? FileManager.default.removeItem(at: database) }

        let held = [ Self.book(id: 1), Self.book(id: 2), Self.book(id: 3) ]

        await store.store(books: held)
        await store.store(series: "Зимпель", workIds: [ 1, 2, 3 ])

        let filed = await store.books().filter { $0.series == "Зимпель" }

        // Which books belong together, and nothing else. Holding two runs together is not an
        // arrangement, and a place written for each of them would stand in front of what the books
        // state about themselves.
        #expect(filed.count == 3)
        #expect(filed.allSatisfy { $0.shelfOrder == nil })
        #expect(filed.allSatisfy { $0.seriesOrder == nil })
    }

    /// Dragging books into an order writes it, counting from one, which is where a series starts.
    @Test
    func arrangingASeriesCountsFromOne() async {
        let database = FileManager.default.temporaryDirectory
            .appendingPathComponent("arranged-\(UUID().uuidString).sqlite")
        let store = SQLiteBookStore(fileURL: database)

        defer { try? FileManager.default.removeItem(at: database) }

        await store.store(books: [ Self.book(id: 1), Self.book(id: 2), Self.book(id: 3) ])
        await store.store(series: "Зимпель", workIds: [ 1, 2, 3 ])
        await store.store(order: [ 3, 1, 2 ], series: "Зимпель")

        let filed = await store.books().filter { $0.series == "Зимпель" }

        #expect(filed.compactMap(\.shelfOrder).sorted() == [ 1, 2, 3 ])
        #expect(filed.first { $0.id == 3 }?.shelfOrder == 1)
    }

    /// A stated nought is absence written as a figure, so it settles nothing about the volumes.
    @Test
    func aStatedNoughtIsNotAVolume() {
        let works = [
            Self.book(id: 1, order: 0),
            Self.book(id: 2, order: 1),
            Self.book(id: 3, order: 2),
        ]
        let group = Model.Group(id: "series:Зимпель", series: "Зимпель", works: works, updated: .now)

        // The book stating nought is drawn with no volume at all rather than as volume nought.
        #expect(group.rows.allSatisfy { row in
            guard case let .book(_, number, _) = row else { return true }

            return number.map { $0 > 0 } ?? true
        })
    }

    /// Volumes the file actually states are still what the shelf draws.
    @Test
    func statedVolumesAreKept() {
        let works = [
            Self.book(id: 1, order: 1),
            Self.book(id: 2, order: 2),
            Self.book(id: 3, order: 3),
        ]
        let group = Model.Group(id: "series:Зимпель", series: "Зимпель", works: works, updated: .now)

        #expect(group.rows.map(\.number) == [ 1, 2, 3 ])
    }

    /// A series the shelf holds one book of is not a run of books, so it is drawn as the book it is.
    /// The row still names the series, which is all the shelf can honestly say about it.
    @Test
    func oneBookOfASeriesIsNotASeries() async {
        let model = await Self.shelf(holding: [ Self.book(id: 1, order: 1) ])

        #expect(model.groups.count == 1)
        #expect(model.groups.first?.series == nil)
    }

    @Test
    func twoBooksOfASeriesAreASeries() async {
        let model = await Self.shelf(holding: [ Self.book(id: 1, order: 1), Self.book(id: 2, order: 2) ])

        #expect(model.groups.count == 1)
        #expect(model.groups.first?.series == "Зимпель")
    }

    /// A shelf reading from a store of its own, holding just these books.
    private static func shelf(holding held: [Book]) async -> LibraryScreen.Model {
        let database = FileManager.default.temporaryDirectory
            .appendingPathComponent("shelf-\(UUID().uuidString).sqlite")
        let store = SQLiteBookStore(fileURL: database)
        let model = LibraryScreen.Model(session: SessionStore(), store: store)

        await store.store(books: held)
        await model.refreshFromStore()
        model.filter = .everything
        return model
    }

    /// A series the reader put together out of books that state no volume is numbered from the bottom,
    /// where a series starts, and keeps the order they arranged. What is filed for each book is its
    /// place in that list, and a place drawn as a volume makes their first pick volume one.
    @Test
    func aSeriesOfUnnumberedBooksIsNumberedFromTheBottom() {
        // Titles that carry no figure, so nothing but the reader's order can number these.
        let works = [
            Self.book(id: 1, title: "Первая", place: 1),
            Self.book(id: 2, title: "Вторая", place: 2),
            Self.book(id: 3, title: "Третья", place: 3),
        ]
        let group = Model.Group(
            id: "series:Зимпель",
            series: "Зимпель",
            works: works,
            updated: .now,
            isCustom: true
        )

        #expect(group.rows.map(\.number) == [ 3, 2, 1 ])
    }

    /// Where the books do state their volumes, those are what the card draws, arranged or not. A book
    /// knows which volume it is; where the reader put it says only where they want it.
    @Test
    func anArrangedSeriesStillDrawsTheVolumesItsBooksState() {
        let works = [
            Self.book(id: 1, order: 7, place: 1),
            Self.book(id: 2, order: 8, place: 2),
        ]
        let group = Model.Group(
            id: "series:Зимпель",
            series: "Зимпель",
            works: works,
            updated: .now,
            isCustom: true
        )

        #expect(group.rows.map(\.number).sorted() == [ 7, 8 ])
    }

    /// A co-author joining a long series partway through leaves the books disagreeing about who wrote
    /// it, and the heading takes the name most of them carry rather than going blank.
    @Test
    func aSeriesIsNamedByTheAuthorMostOfItsBooksCarry() {
        let works = [
            Self.book(id: 1, author: "Имя Фамилия, Второе Имя"),
            Self.book(id: 2, author: "Имя Фамилия"),
            Self.book(id: 3, author: "Имя Фамилия"),
        ]
        let group = Model.Group(id: "series:Зимпель", series: "Зимпель", works: works, updated: .now)

        #expect(group.author == "Имя Фамилия")
    }

    /// Where they disagree evenly, the book the card leads with is the one being read.
    @Test
    func anEvenDisagreementTakesTheLeadingBooksAuthor() {
        let works = [ Self.book(id: 1, author: "Первый Автор"), Self.book(id: 2, author: "Второй Автор") ]
        let group = Model.Group(id: "series:Зимпель", series: "Зимпель", works: works, updated: .now)

        #expect(group.author == "Первый Автор")
    }

    /// A series the reader arranged still says which of its volumes are absent.
    ///
    /// What they arranged is the order the books stand in. The numbers are the titles' own, and only
    /// those can say a volume is missing: a place counted off the rows has no gaps in it by
    /// definition, since every row has one.
    @Test
    func aseriesTheReaderArrangedStillShowsWhatIsMissing() async {
        let works = [
            Self.book(id: 1, title: "Зимпель 1. Первая"),
            Self.book(id: 3, title: "Зимпель 3. Третья"),
        ]
        let database = FileManager.default.temporaryDirectory
            .appendingPathComponent("arranged-\(UUID().uuidString).sqlite")
        let store = SQLiteBookStore(fileURL: database)
        let model = LibraryScreen.Model(session: SessionStore(), store: store)

        defer { try? FileManager.default.removeItem(at: database) }

        await store.store(books: works)
        await store.store(series: "Зимпель", workIds: [ 1, 3 ])
        await model.refreshFromStore()
        model.filter = .everything

        let rows = model.groups.first?.rows ?? []

        #expect(rows.contains { if case .missing(2) = $0 { true } else { false } })
    }

    /// Two parts of one volume share its number and belong side by side. Asking that every stated
    /// volume be different throws the whole numbering away for the one thing it cannot express.
    @Test
    func twoPartsOfOneVolumeStandTogether() {
        let works = [
            Self.book(id: 1, order: 4, title: "Хаген. Нокаут 1"),
            Self.book(id: 2, order: 2, title: "Герой"),
            Self.book(id: 3, order: 4, title: "Хаген. Нокаут 2"),
            Self.book(id: 4, order: 1, title: "Рестарт"),
        ]
        let group = Model.Group(
            id: "series:Зимпель",
            series: "Зимпель",
            works: Model.ordered(works, arrangedByHand: true),
            updated: .now,
            isCustom: true
        )

        // Volume three is nowhere in the fixture, so the shelf says so between four and two.
        #expect(group.rows.map(\.number) == [ 4, 4, 3, 2, 1 ])
        #expect(group.rows.compactMap(Self.title) == [ "Хаген. Нокаут 2", "Хаген. Нокаут 1", "Герой", "Рестарт" ])
    }

    private static func title(_ row: Model.SeriesRow) -> String? {
        guard case let .book(_, _, title) = row else { return nil }

        return title
    }

    private static func book(
        id: Int,
        order: Int? = nil,
        author: String = "Имя Фамилия",
        title: String? = nil,
        place: Int? = nil
    ) -> Book {
        Book(
            id: id,
            title: title ?? "Зимпель \(id)",
            authorLine: author,
            coverURL: nil,
            annotation: nil,
            seriesTitle: "Зимпель",
            seriesOrder: order,
            shelfOrder: place,
            textLength: 1000,
            likeCount: nil,
            isFinished: true,
            status: nil,
            isPurchased: nil,
            adultOnly: nil,
            lastUpdateTime: .now,
            readingProgress: 0,
            hasStartedReading: false,
            lastReadTime: nil,
            lastChapterId: nil,
            libraryState: .reading
        )
    }
}
