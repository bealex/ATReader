//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import Foundation
import Testing

@testable import ATReader

/// Where a book's volume number comes from, and what it may not be.
///
/// A series counts from one, so nought is not a place in one. It reached the shelf as a place counted
/// from zero and was drawn as a volume, which put a book nought at the head of every series the reader
/// assembled and moved every volume after it down by one.
@MainActor
struct SeriesOrderTests {
    private typealias Model = LibraryScreen.Model

    @Test
    func aSeriesTheReaderAssemblesCountsFromOne() async {
        let database = FileManager.default.temporaryDirectory
            .appendingPathComponent("series-\(UUID().uuidString).sqlite")
        let store = SQLiteBookStore(fileURL: database)

        defer { try? FileManager.default.removeItem(at: database) }

        let held = [ Self.book(id: 1), Self.book(id: 2), Self.book(id: 3) ]

        await store.store(books: held)
        await store.store(series: "Зимпель", workIds: [ 1, 2, 3 ])

        let filed = await store.books().filter { $0.series == "Зимпель" }

        #expect(filed.compactMap(\.seriesOrder).sorted() == [ 1, 2, 3 ])
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

        #expect(group.rows.allSatisfy { $0.number > 0 })
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

    private static func book(id: Int, order: Int? = nil) -> Book {
        Book(
            id: id,
            title: "Зимпель \(id)",
            authorLine: "Имя Фамилия",
            coverURL: nil,
            annotation: nil,
            seriesTitle: "Зимпель",
            seriesOrder: order,
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
