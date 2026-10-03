//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import BookStorage
import Foundation
import Testing

@testable import Bookhold

/// Which books of a series count as new, and which series are watched at all.
struct SeriesWatchTests {
    @Test
    func aSeriesMetForTheFirstTimeHasNothingNew() {
        #expect(SeriesWatch.fresh(listed: [ 1, 2, 3 ], held: [ 1 ], seen: nil).isEmpty)
    }

    @Test
    func aBookListedAfterTheSeriesWasSeenIsNew() {
        #expect(SeriesWatch.fresh(listed: [ 1, 2, 3 ], held: [ 1 ], seen: [ 1, 2 ]) == [ 3 ])
    }

    @Test
    func aBookTheReaderTookOffTheShelfStaysOff() {
        #expect(SeriesWatch.fresh(listed: [ 1, 2 ], held: [ 1 ], seen: [ 1, 2 ]).isEmpty)
    }

    @Test
    func aHeldBookIsNeverNew() {
        #expect(SeriesWatch.fresh(listed: [ 1, 2 ], held: [ 1, 2 ], seen: [ 1 ]).isEmpty)
    }

    @Test
    func eachKeptSeriesIsAskedAboutThroughItsLatestBook() throws {
        let library = try [
            Self.work(id: 10, series: 7, order: 0, state: "Finished"),
            Self.work(id: 11, series: 7, order: 1, state: "Saved"),
            Self.work(id: 20, series: 8, order: 0, state: "Disliked"),
            Self.work(id: 30, series: nil, order: nil, state: "Reading"),
        ]

        #expect(SeriesWatch.watched(in: library) == [ 7: 11 ])
    }

    @Test
    func theStoreRemembersWhatEachSeriesHeld() async {
        let database = FileManager.default.temporaryDirectory
            .appendingPathComponent("series-seen-\(UUID().uuidString).sqlite")
        let store = SQLiteBookStore(fileURL: database)

        defer { try? FileManager.default.removeItem(at: database) }

        await store.markSeen(workIds: [ 1, 2 ], inSeries: 7)
        await store.markSeen(workIds: [ 2, 3 ], inSeries: 7)
        await store.markSeen(workIds: [ 4 ], inSeries: 8)

        #expect(await store.seenSeriesBooks() == [ 7: [ 1, 2, 3 ], 8: [ 4 ] ])
    }

    private static func work(id: Int, series: Int?, order: Int?, state: String) throws -> WorkMetaInfo {
        var fields: [String: Any] = [ "id": id, "title": "Lorem \(id)", "inLibraryState": state ]

        fields["seriesId"] = series
        fields["seriesOrder"] = order

        return try JSONDecoder().decode(WorkMetaInfo.self, from: JSONSerialization.data(withJSONObject: fields))
    }
}
