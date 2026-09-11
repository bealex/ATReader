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

    /// Runs by different writers, held together by hand, stand whole on each writer's own card.
    @Test
    func acombinedSeriesStandsOnEachWritersCard() async throws {
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
        let first = try #require(model.allSeries.first { $0.author == "Первый Автор" })
        let second = try #require(model.allSeries.first { $0.author == "Второй Автор" })

        await model.merge([ first, second ], named: "Вместе")

        #expect(Set(model.shelves.map(\.name)) == [ "Первый Автор", "Второй Автор" ])
        #expect(model.shelves.allSatisfy { $0.runs.map(\.series) == [ "Вместе" ] && $0.works.count == 4 })
    }

    /// A book whose file leaves its series out joins the run once the reader names the series, at the
    /// volume they give it, and leaves again when they take the correction back.
    @Test
    func abookGivenItsSeriesByHandJoinsTheRun() async throws {
        let database = FileManager.default.temporaryDirectory
            .appendingPathComponent("edit-\(UUID().uuidString).sqlite")
        let store = SQLiteBookStore(fileURL: database)
        let model = Model(session: SessionStore(), store: store)

        defer { try? FileManager.default.removeItem(at: database) }

        var loose = Self.book(id: 3, title: "Третья")

        loose.seriesTitle = nil
        await store.store(books: [
            Self.book(id: 1, title: "Первая", volume: 1),
            Self.book(id: 2, title: "Вторая", volume: 2),
            loose,
        ])
        await store.store(seriesEdit: .init(series: "Зимпель", volume: 3), workId: 3)
        await model.refreshFromStore()
        model.filter = .everything

        let run = try #require(model.groups.first { $0.series == "Зимпель" })

        #expect(run.rows.map(\.number) == [ 3, 2, 1 ])

        await store.store(seriesEdit: nil, workId: 3)
        await model.refreshFromStore()

        #expect(model.groups.first { $0.series == "Зимпель" }?.works.count == 2)
    }

    /// Naming a merged series joins it, naming another leaves it, and taking the correction back
    /// returns the book to the series it came with.
    @Test
    func correctingASeriesJoinsAndLeavesAMergedOne() async throws {
        let database = FileManager.default.temporaryDirectory
            .appendingPathComponent("correct-\(UUID().uuidString).sqlite")
        let store = SQLiteBookStore(fileURL: database)
        let model = Model(session: SessionStore(), store: store)

        defer { try? FileManager.default.removeItem(at: database) }

        await store.store(books: [
            Self.book(id: 1, title: "Первая", volume: 1),
            Self.book(id: 2, title: "Вторая", volume: 2),
            Self.book(id: 3, title: "Чужая", series: "Другая"),
        ])
        await store.store(series: "Вместе", workIds: [ 1, 2 ])
        await SeriesCorrection.save(.init(series: "Вместе", volume: 3), for: 3, store: store)
        await SeriesCorrection.save(.init(series: "Своя", volume: nil), for: 1, store: store)
        await model.refreshFromStore()
        model.filter = .everything

        let merged = try #require(model.groups.first { $0.series == "Вместе" })

        #expect(Set(merged.works.map(\.id)) == [ 2, 3 ])
        #expect(merged.volumes[3] == 3)
        #expect(model.works.first { $0.id == 1 }?.series == "Своя")
        #expect(Set(await store.seriesEdits().keys) == [ 1, 2, 3 ])
        // A volume left alone is the one the book states.
        #expect(model.works.first { $0.id == 1 }?.seriesOrder == 1)

        await SeriesCorrection.save(nil, for: 3, store: store)
        await model.refreshFromStore()

        #expect(model.works.first { $0.id == 3 }?.series == "Другая")
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

    /// A volume whose co-author is named first still belongs to the series its writer is running.
    @Test
    func avolumeWithItsCoauthorNamedFirstStaysInTheSeries() async throws {
        let model = await Self.shelf(holding: [
            Self.book(id: 1, title: "Первая", author: "Первый Автор", volume: 1),
            Self.book(id: 2, title: "Вторая", author: "Второй Автор, Первый Автор", volume: 2),
            Self.book(id: 3, title: "Третья", author: "Первый Автор", volume: 3),
        ])

        let run = try #require(model.groups.first { $0.series == "Зимпель" })

        #expect(model.groups.count == 1)
        #expect(run.rows.map(\.number) == [ 3, 2, 1 ])
    }

    /// A book two writers wrote stands on both their cards; the rest of the series stays with its writer.
    @Test
    func acowrittenBookStandsOnEveryWritersCard() async throws {
        let model = await Self.shelf(holding: [
            Self.book(id: 1, title: "Первая", author: "Первый Автор"),
            Self.book(id: 2, title: "Вторая", author: "Первый Автор, Второй Автор"),
            Self.book(id: 3, title: "Своя", author: "Второй Автор", series: "Другая"),
        ])

        let first = try #require(model.shelves.first { $0.name == "Первый Автор" })
        let second = try #require(model.shelves.first { $0.name == "Второй Автор" })

        #expect(model.shelves.count == 2)
        #expect(Set(first.works.map(\.id)) == [ 1, 2 ])
        #expect(Set(second.works.map(\.id)) == [ 2, 3 ])
    }

    /// A co-author who leads no book of their own gets no card: an anthology would deal one to everyone.
    @Test
    func acoauthorWithNoBookOfTheirOwnGetsNoCard() async {
        let model = await Self.shelf(holding: [
            Self.book(id: 1, title: "Первая", author: "Первый Автор, Второй Автор"),
        ])

        #expect(model.shelves.map(\.name) == [ "Первый Автор" ])
    }

    /// A series written together from its first book stands whole on both cards.
    @Test
    func aseriesWrittenTogetherStandsWholeOnBothCards() async {
        let model = await Self.shelf(holding: [
            Self.book(id: 1, title: "Первая", author: "Первый Автор, Второй Автор"),
            Self.book(id: 2, title: "Вторая", author: "Первый Автор, Второй Автор"),
            Self.book(id: 3, title: "Своя", author: "Второй Автор", series: "Другая"),
        ])

        #expect(model.shelves.count == 2)
        #expect(model.shelves.allSatisfy { shelf in shelf.runs.contains { $0.series == "Зимпель" && $0.works.count == 2 } })
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
        author: String = "Имя Фамилия",
        series: String = "Зимпель",
        volume: Int? = nil
    ) -> Book {
        Book(
            id: id,
            title: title,
            authorLine: author,
            coverURL: nil,
            annotation: nil,
            seriesTitle: series,
            seriesOrder: volume,
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
