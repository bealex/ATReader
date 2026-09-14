//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import DesignSystem
import Testing
import UIKit

@testable import Bookhold

/// The library's own list, told its books now stand a different way round.
///
/// A card changing height is the part only the list can get right: it is told its height rather than
/// asked for it, so nothing carries the card unless the list carries it. What went wrong was an order
/// of operations, which nothing but a measurement through the collection view catches.
@MainActor
struct ShelfStepTests {
    private static let across: CGFloat = 402

    private func card(of count: Int, standingOut: Int?, everyCover: Bool = false) -> AuthorCardView.Contents {
        let works = (1 ... count).map { id in
            Book(
                id: id,
                title: "Title \(id)",
                authorLine: "Author",
                coverURL: nil,
                annotation: nil,
                textLength: 300_000 + id * 60_000
            )
        }

        return AuthorCardView.Contents(
            id: "author",
            name: "Author",
            shelf: ShelfView.Contents(
                runs: [
                    ShelfRun(
                        id: "run",
                        title: "Series",
                        slots: works.map {
                            .book($0, number: $0.id, title: "Title \($0.id)", isShelved: $0.id != standingOut)
                        }
                    ),
                ],
                alone: [],
                coverWidth: Design.Size.gridCover,
                showsEveryCover: everyCover
            )
        )
    }

    private func list(_ card: AuthorCardView.Contents) -> LibraryList {
        LibraryList(
            cards: [ card ],
            chrome: LibraryList.Chrome(empty: nil),
            onOpen: { _, _ in },
            onName: { _ in },
            onTurn: { _ in },
            bookMenu: { _, _ in nil },
            runMenu: { _ in nil },
            authorMenu: { _ in nil },
            onRefresh: {}
        )
    }

    /// A list showing one card, told the same card once already: a card whose books have never been
    /// seen standing is redrawn rather than turned, which is what the app's first update does.
    private func shown(_ card: AuthorCardView.Contents) async throws -> (LibraryList.Coordinator, UIViewController) {
        let coordinator = list(card).makeCoordinator()
        let controller = coordinator.make()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: Self.across, height: 874))

        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        try await Task.sleep(for: .milliseconds(200))

        coordinator.show(list(card))
        controller.view.layoutIfNeeded()

        return (coordinator, controller)
    }

    /// How tall the one card stands, after the layout pass the run loop would have made.
    private func height(_ controller: UIViewController) -> CGFloat {
        controller.view.layoutIfNeeded()

        let cell = (controller as? UICollectionViewController)?
            .collectionView
            .cellForItem(at: IndexPath(item: 0, section: 0))

        return cell?.frame.height ?? 0
    }

    /// Putting a book away takes a row off this card, and the card travels to its new height rather
    /// than arriving there in the frame the list is told.
    @Test
    func carriesTheCardToItsNewHeight() async throws {
        let (coordinator, controller) = try await shown(card(of: 11, standingOut: 5))
        let before = height(controller)

        coordinator.show(list(card(of: 11, standingOut: nil)))

        let first = height(controller)

        try await Task.sleep(for: .seconds(FoldMotion.turningSeconds + 0.3))

        let after = height(controller)

        #expect(before != after, "the card is the same height either way, so this proves nothing")
        #expect(abs(first - before) < 0.5, "the card was at its new height in the first frame")
    }

    /// And the whole card turned round, which moves every book on it and every row it stands in.
    @Test
    func carriesTheCardThroughAFold() async throws {
        let (coordinator, controller) = try await shown(card(of: 11, standingOut: nil))
        let before = height(controller)

        coordinator.show(list(card(of: 11, standingOut: nil, everyCover: true)))

        #expect(abs(height(controller) - before) < 0.5, "the card was at its new height in the first frame")

        try await Task.sleep(for: .seconds(FoldMotion.turningSeconds * 0.4))

        let during = height(controller)

        try await Task.sleep(for: .seconds(FoldMotion.turningSeconds))

        let after = height(controller)

        #expect(before != after, "the card is the same height either way, so this proves nothing")
        #expect(during > before && during < after, "the card never travelled: it stood at \(during)")
    }
}
