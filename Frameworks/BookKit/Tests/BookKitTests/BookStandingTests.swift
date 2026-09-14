//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import Testing

@testable import BookKit

/// Which books stand out as covers and which have been put away.
struct BookStandingTests {
    @Test
    func aBookReadThroughStandsOutForTheDay() {
        let read = book(progress: 1, readAt: .now)

        #expect(read.isStandingOut())
        #expect(!read.isDone())

        let older = book(progress: 1, readAt: .now.addingTimeInterval(-Book.standingOut - 1))

        #expect(!older.isStandingOut())
        #expect(older.isDone())
    }

    @Test
    func puttingABookAwayEndsItsDayEarly() {
        let now = Date.now
        let away = book(progress: 1, readAt: now, takenDownAt: now, putAwayAt: now)

        #expect(away.isPutAway)
        #expect(!away.isStandingOut())
        #expect(away.isDone())
    }

    /// Marking a book read and putting it away in one go leaves it away.
    ///
    /// Reading it through is what puts a book out as a cover for the day, so the two have to happen in
    /// that order: put away first and the reading would stand it straight back out.
    @Test
    func beingDoneWithABookInOneGoStandsItOnItsEdge() {
        let read = Date.now
        let away = book(progress: 1, readAt: read, putAwayAt: read.addingTimeInterval(0.01))

        #expect(away.isReadToTheEnd)
        #expect(away.isPutAway)
        #expect(!away.isStandingOut(), "the book it was done with stood out as a cover anyway")
        #expect(away.isDone())
    }

    /// A book on the Finished shelf is read through, whatever its progress says.
    ///
    /// The count is worked out again from where the reader stands and can be lost; the shelf is what
    /// the reader said. A book that loses its count is not a book they never read.
    @Test
    func takesTheShelfsWordOverTheCount() {
        var filed = book(progress: 0)

        #expect(!filed.isReadToTheEnd)
        #expect(!filed.isDone(), "a book with nothing read is not done")

        filed.libraryState = .finished

        #expect(filed.isReadToTheEnd)
        #expect(!filed.isBeingRead, "a finished book was counted as still being read")
        #expect(filed.isDone())
    }

    /// Opening the book again puts it back on the board, whatever was asked for before.
    @Test
    func openingAPutAwayBookStandsItOutAgain() {
        let now = Date.now
        let back = book(progress: 1, readAt: now, takenDownAt: now.addingTimeInterval(60), putAwayAt: now)

        #expect(!back.isPutAway)
        #expect(back.isStandingOut())
        #expect(!back.isDone())
    }

    private func book(
        progress: Double,
        readAt: Date? = nil,
        takenDownAt: Date? = nil,
        putAwayAt: Date? = nil
    ) -> Book {
        var made = Book(
            id: 11,
            title: "Echo",
            authorLine: "Foxtrot",
            coverURL: nil,
            annotation: nil,
            isFinished: true,
            readingProgress: progress
        )

        made.readAt = readAt
        made.takenDownAt = takenDownAt
        made.putAwayAt = putAwayAt
        return made
    }
}
