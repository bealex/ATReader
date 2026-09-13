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
