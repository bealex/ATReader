//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import DesignSystem
import Testing
import UIKit

@testable import Librix

/// A shelf turning its books from their spines to their covers.
///
/// The turn is the one thing on this screen that cannot be read off the code: what is written is a
/// clock, and what matters is that the books are somewhere between their two ends while it runs. It has
/// twice been cancelled by a layout pass instead, which nothing but a measurement catches.
@MainActor
struct ShelfTurnTests {
    private func contents(showsEveryCover: Bool) -> ShelfView.Contents {
        let works = (1 ... 6).map { id in
            Book(
                id: id,
                title: "Title \(id)",
                authorLine: "Author",
                coverURL: nil,
                annotation: nil,
                textLength: 500_000
            )
        }

        return ShelfView.Contents(
            runs: [
                ShelfRun(
                    id: "run",
                    title: "Series",
                    slots: works.map { .book($0, number: $0.id, title: "Title \($0.id)", isShelved: true) }
                )
            ],
            alone: [],
            coverWidth: Design.Size.gridCover,
            showsEveryCover: showsEveryCover
        )
    }

    private func shelf() -> ShelfView {
        let shelf = ShelfView()

        shelf.frame = CGRect(x: 0, y: 0, width: 300, height: 400)
        shelf.show(contents(showsEveryCover: false))
        shelf.layoutIfNeeded()

        return shelf
    }

    @Test
    func standsEveryReadBookOnItsEdgeToBeginWith() {
        #expect(shelf().turns.values.allSatisfy { $0 == 0 })
    }

    @Test
    func startsTheTurnWhereTheBooksWereRatherThanWhereTheyAreGoing() {
        let shelf = shelf()

        shelf.turn(to: contents(showsEveryCover: true), animated: true)

        #expect(shelf.turns.values.allSatisfy { $0 < 0.5 }, "the books arrived before the turn began")
    }

    @Test
    func keepsTheTurnThroughALayout() {
        let shelf = shelf()

        shelf.turn(to: contents(showsEveryCover: true), animated: true)
        // What cancelled it before: turning changes how tall a card is, so something lays the shelf out
        // again the moment a turn starts.
        shelf.setNeedsLayout()
        shelf.layoutIfNeeded()

        #expect(shelf.turns.values.allSatisfy { $0 < 0.5 }, "a layout in the middle of a turn ended it")
    }

    @Test
    func landsFlatOnceTheTurnIsOver() async throws {
        let shelf = shelf()

        shelf.turn(to: contents(showsEveryCover: true), animated: true)

        try await Task.sleep(for: .seconds(FoldMotion.turningSeconds + 0.3))

        #expect(shelf.turns.values.allSatisfy { $0 > 0.99 }, "the turn never finished")
    }

    @Test
    func knowsItsHeightBeforeItHasEverBeenLaidOut() {
        let card = AuthorCardView()
        let shelved = AuthorCardView.Contents(
            id: "author",
            name: "Author",
            shelf: contents(showsEveryCover: false)
        )

        // Never given a size: this is what the list asks a card the first time it lays one out, and a
        // card that answers from its own bounds answers for a shelf no wider than nothing.
        card.show(shelved)

        #expect(card.height(across: 350) == AuthorCardView.height(shelved, across: 350))
    }

    @Test
    func carriesTheCardsOwnHeightThroughTheTurn() {
        let card = AuthorCardView()
        let across: CGFloat = 350
        let shelved = AuthorCardView.Contents(
            id: "author",
            name: "Author",
            shelf: contents(showsEveryCover: false)
        )
        let taken = AuthorCardView.Contents(
            id: "author",
            name: "Author",
            shelf: contents(showsEveryCover: true)
        )

        card.frame = CGRect(x: 0, y: 0, width: across, height: AuthorCardView.height(shelved, across: across))
        card.show(shelved)
        card.layoutIfNeeded()

        let before = card.height(across: across)
        let after = AuthorCardView.height(taken, across: across)

        #expect(before != after, "the two ways round are the same height, so this proves nothing")

        card.turn(to: taken, animated: true)

        let during = card.height(across: across)

        #expect(
            abs(during - before) < abs(during - after),
            "the card was at its new height in the first frame, so nothing carried it there"
        )
    }

    @Test
    func turnsAtOnceWhereNoAnimationWasAskedFor() {
        let shelf = shelf()

        shelf.turn(to: contents(showsEveryCover: true), animated: false)
        shelf.layoutIfNeeded()

        #expect(shelf.turns.values.allSatisfy { $0 == 1 })
    }
}
