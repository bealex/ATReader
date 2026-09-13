//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Foundation
import Testing

@testable import Bookhold

/// What the shelf's filters keep, and what they hide.
///
/// A card is kept or hidden whole, so a series is judged by everything in it rather than book by book.
/// The books are generated: only what has been read and whether the author has finished matters here.
struct LibraryFilterTests {
    private typealias Filter = LibraryScreen.Model.Filter

    // MARK: - One book on its own

    @Test
    func readingKeepsABookWithSomethingLeft() {
        #expect(Filter.reading.includes([ Self.book(read: 0.4, isFinished: true) ]))
    }

    @Test
    func readingHidesABookReadToItsEnd() {
        #expect(!Filter.reading.includes([ Self.book(read: 1, isFinished: true) ]))
    }

    /// Read to the end of a book the author is still writing is not finished with it.
    @Test
    func readingKeepsABookStillBeingWritten() {
        #expect(Filter.reading.includes([ Self.book(read: 1, isFinished: false) ]))
    }

    // MARK: - A series

    /// The point of the whole rule: one unread book keeps the series, and it arrives entire.
    @Test
    func readingKeepsAWholeSeriesForOneUnreadBook() {
        let series = [
            Self.book(read: 1, isFinished: true),
            Self.book(read: 1, isFinished: true),
            Self.book(read: 0.2, isFinished: true),
        ]

        #expect(Filter.reading.includes(series))
    }

    @Test
    func readingHidesASeriesReadToItsLastBook() {
        let series = [
            Self.book(read: 1, isFinished: true),
            Self.book(read: 1, isFinished: true),
        ]

        #expect(!Filter.reading.includes(series))
    }

    /// A series read right through is off the Reading shelf; one with anything left in it is not.
    @Test
    func readingLeavesASeriesOnlyWhenNothingIsLeftInIt() {
        let done = [ Self.book(read: 1, isFinished: true), Self.book(read: 1, isFinished: true) ]
        let partly = [ Self.book(read: 1, isFinished: true), Self.book(read: 0.2, isFinished: true) ]

        #expect(!Filter.reading.includes(done))
        #expect(Filter.reading.includes(partly))
    }

    /// All books is where a reader goes to find whatever the shelf is not showing, so it keeps every
    /// card whatever has been read of it.
    @Test(arguments: [
        [ 0.1 ], [ 1.0 ], [ 1.0, 1.0 ], [ 1.0, 0.3 ], [ 0.2, 0.4 ],
    ])
    func everythingKeepsEveryCard(progress: [Double]) {
        #expect(Filter.everything.includes(progress.map { Self.book(read: $0, isFinished: true) }))
    }

    // MARK: - Hiding what a series holds

    /// The shelf keeps the book of a series the reader is on, and drops the rest of it: the ones they
    /// have finished with as well as the ones they have never opened.
    @Test
    func hidingASeriesKeepsOnlyWhatIsBeingRead() {
        var done = Self.book(read: 1, isFinished: true)
        done.readAt = .now.addingTimeInterval(-2 * 24 * 60 * 60)

        let reading = Self.book(read: 0.4, isFinished: true)
        let series = [ reading, Self.book(read: 0, isFinished: true), done ]
        let kept = LibraryScreen.Model.beingRead(among: series).map(\.id)

        #expect(kept == [ reading.id ])
    }

    /// Read to the end of a book the author is still writing is still being read.
    @Test
    func hidingASeriesKeepsABookTheReaderIsCaughtUpWith() {
        let caughtUp = Self.book(read: 1, isFinished: false)
        let series = [ caughtUp, Self.book(read: 0, isFinished: true) ]

        #expect(LibraryScreen.Model.beingRead(among: series).map(\.id) == [ caughtUp.id ])
    }

    /// A book that arrived in the last day stands out wherever it is, opened or not.
    @Test
    func hidingASeriesKeepsABookThatJustArrived() {
        var arrived = Self.book(read: 0, isFinished: true)
        arrived.takenDownAt = .now

        let series = [ Self.book(read: 0.4, isFinished: true), arrived ]

        #expect(LibraryScreen.Model.beingRead(among: series).contains { $0.id == arrived.id })
    }

    @Test
    func hidingASeriesDropsABookThatArrivedLongerAgo() {
        var older = Self.book(read: 0, isFinished: true)
        older.takenDownAt = .now.addingTimeInterval(-2 * 24 * 60 * 60)

        let series = [ Self.book(read: 0.4, isFinished: true), older ]

        #expect(!LibraryScreen.Model.beingRead(among: series).contains { $0.id == older.id })
    }

    /// A single book is not a series on the shelf, so hiding series never hides it.
    @Test
    func hidingASeriesLeavesALoneBookAlone() {
        let alone = [ Self.book(read: 0, isFinished: true) ]

        #expect(LibraryScreen.Model.beingRead(among: alone).count == 1)
    }

    /// A series nobody has opened has nothing left to show, and goes off the shelf entire.
    @Test
    func hidingASeriesNobodyOpenedLeavesNothing() {
        let series = [ Self.book(read: 0, isFinished: true), Self.book(read: 0, isFinished: true) ]

        #expect(LibraryScreen.Model.beingRead(among: series).isEmpty)
    }

    /// A card cut down to what is being read draws no gaps: every book it dropped would come straight
    /// back as a volume the shelf says it hasn't got.
    @Test
    func aCutDownCardDrawsNoMissingVolumes() {
        let held = [ Self.volume(1), Self.volume(5) ]
        let whole = Self.run(held, isWhole: true)
        let cut = Self.run(held, isWhole: false)

        #expect(whole.rows.contains { if case .missing = $0 { true } else { false } })
        #expect(cut.rows.allSatisfy { if case .book = $0 { true } else { false } })
        #expect(cut.rows.count == held.count)
    }

    // MARK: - A book to file

    private static func run(_ works: [Book], isWhole: Bool) -> LibraryScreen.Model.Group {
        LibraryScreen.Model.Group(
            id: "series:Ember",
            series: "Ember",
            works: works,
            updated: .now,
            isWhole: isWhole
        )
    }

    private static func volume(_ number: Int) -> Book {
        var work = book(read: 0.5, isFinished: true)

        work = Book(
            id: work.id,
            title: "Книга \(number)",
            authorLine: "Автор",
            coverURL: nil,
            annotation: nil,
            seriesTitle: "Ember",
            seriesOrder: number,
            textLength: 1000,
            isFinished: true,
            lastUpdateTime: .now,
            readingProgress: 0.5,
            hasStartedReading: true,
            libraryState: .reading
        )

        return work
    }

    private static func book(read: Double, isFinished: Bool) -> Book {
        Book(
            id: Int.random(in: 1 ... 1_000_000),
            title: "Книга",
            authorLine: "Автор",
            coverURL: nil,
            annotation: nil,
            seriesTitle: nil,
            seriesOrder: nil,
            textLength: 1000,
            likeCount: nil,
            isFinished: isFinished,
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
