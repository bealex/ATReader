//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import Testing

@testable import ATReader

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

    /// A series is finished only when every book in it is, so the two filters never both claim one.
    @Test
    func finishedTakesOnlyASeriesReadRightThrough() {
        let done = [ Self.book(read: 1, isFinished: true), Self.book(read: 1, isFinished: true) ]
        let partly = [ Self.book(read: 1, isFinished: true), Self.book(read: 0.2, isFinished: true) ]

        #expect(Filter.finished.includes(done))
        #expect(!Filter.finished.includes(partly))
    }

    /// Every card lands under exactly one of the two, which is what makes the pair a division of the
    /// shelf rather than two overlapping views of it.
    @Test(arguments: [
        [ 0.1 ], [ 1.0 ], [ 1.0, 1.0 ], [ 1.0, 0.3 ], [ 0.2, 0.4 ],
    ])
    func everyCardIsUnderOneFilterOrTheOther(progress: [Double]) {
        let works = progress.map { Self.book(read: $0, isFinished: true) }

        #expect(Filter.reading.includes(works) != Filter.finished.includes(works))
        #expect(Filter.everything.includes(works))
    }

    // MARK: - A book to file

    private static func book(read: Double, isFinished: Bool) -> WorkSummary {
        WorkSummary(
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
