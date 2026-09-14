//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import DesignSystem
import Testing
import UIKit

@testable import Bookhold

/// One book put away, which stands it on its edge and closes up every book after it.
///
/// The run wraps, so putting a book away in the middle of it moves the books that no longer fit their
/// row to the row above. That move is the one a shelf cannot make by sliding: a straight line between
/// two rows runs over the plank and through the books it is joining.
@MainActor
struct ShelfPutAwayTests {
    private static let across: CGFloat = 360

    private func contents(standingOut: Int?) -> ShelfView.Contents {
        let works = (1 ... 16).map { id in
            Book(
                id: id,
                title: "Title \(id)",
                authorLine: "Author",
                coverURL: nil,
                annotation: nil,
                textLength: 300_000 + id * 60_000
            )
        }

        return ShelfView.Contents(
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
            showsEveryCover: false
        )
    }

    private func shelf(standingOut: Int?) -> ShelfView {
        let shelf = ShelfView()

        shelf.frame = CGRect(x: 0, y: 0, width: Self.across, height: 900)
        shelf.show(contents(standingOut: standingOut))
        shelf.layoutIfNeeded()

        return shelf
    }

    /// The feet of the rows, which is the only height a book ever stands at.
    private func feet(_ shelf: ShelfView) -> Set<CGFloat> { Set(shelf.stands.values.map(\.maxY)) }

    /// The book put away is in the middle of the run, so this moves books between rows.
    @Test
    func movesBooksBetweenRowsAtAll() {
        let before = feet(shelf(standingOut: 6))
        let after = feet(shelf(standingOut: nil))

        #expect(before.count > 1, "the run does not wrap, so this proves nothing")
        #expect(before != after || rowsDiffer(), "no book changes row, so this proves nothing")
    }

    /// Whether the two ways round put a different number of books on the first row.
    private func rowsDiffer() -> Bool {
        let top = { (shelf: ShelfView) in shelf.stands.values.filter { $0.maxY == feet(shelf).min() }.count }

        return top(shelf(standingOut: 6)) != top(shelf(standingOut: nil))
    }

    /// No book is ever drawn between two rows: one that changes row is re-shelved rather than flown
    /// across the bookcase.
    @Test
    func neverStandsABookBetweenTwoRows() async throws {
        let shelf = shelf(standingOut: 6)
        let standing = feet(shelf).union(feet(self.shelf(standingOut: nil)))

        shelf.turn(to: contents(standingOut: nil), animated: true)

        for _ in 0 ..< 6 {
            for (id, frame) in shelf.stands {
                #expect(
                    standing.contains(where: { abs($0 - frame.maxY) < 0.5 }),
                    "\(id) stood at \(frame.maxY), which is no row"
                )
            }

            try await Task.sleep(for: .seconds(FoldMotion.turningSeconds / 6))
        }
    }

    /// The book being put away turns where it stands, about the edge its spine will stand on.
    @Test
    func turnsTheBookWhereItStands() async throws {
        let shelf = shelf(standingOut: 6)
        let stood = try #require(shelf.stands["book:6"])

        #expect(shelf.turns["book:6"] == 1)

        shelf.turn(to: contents(standingOut: nil), animated: true)

        try await Task.sleep(for: .seconds(FoldMotion.turningSeconds / 3))

        let turning = try #require(shelf.turns["book:6"])

        #expect(turning > 0 && turning < 1, "the book was not part way round")
        #expect(abs((shelf.stands["book:6"]?.minX ?? 0) - stood.minX) < 0.5, "the book turned off its own edge")
    }

    /// Where the turn leaves every book is where a shelf laid out afresh puts it, so nothing steps when
    /// the next layout comes round.
    @Test
    func landsWhereAFreshLayoutPutsEveryBook() async throws {
        let shelf = shelf(standingOut: 6)

        shelf.turn(to: contents(standingOut: nil), animated: true)

        try await Task.sleep(for: .seconds(FoldMotion.turningSeconds + 0.3))

        let landed = shelf.stands

        shelf.setNeedsLayout()
        shelf.layoutIfNeeded()

        for (id, frame) in shelf.stands {
            let stood = try #require(landed[id])

            #expect(stood.isWhere(frame), "\(id) stepped from \(stood) to \(frame)")
        }

        #expect(shelf.turns.values.allSatisfy { $0 == 0 })
    }

    /// A book with no menu up does what it is asked at once.
    @Test
    func doesWhatItIsAskedWhereNoMenuIsUp() {
        let view = BookView()
        var did = false

        view.whenMenuCloses { did = true }

        #expect(did)
    }

    /// A book with a menu up holds the work until the menu has closed, because UIKit is putting the
    /// lifted book back in the meantime and the shelf would be moving the same book.
    @Test
    func holdsWorkUntilItsMenuHasClosed() {
        let view = BookView()
        let interaction = UIContextMenuInteraction(delegate: view)
        let configuration = UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: nil)
        var did = false

        view.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: nil)
        view.whenMenuCloses { did = true }

        #expect(!did, "the book moved while its menu was still on the screen")

        view.contextMenuInteraction(interaction, willEndFor: configuration, animator: nil)

        #expect(did, "the book never did what the menu asked")
    }
}

private extension CGRect {
    /// Whether this is the same place as another, to closer than a reader could see.
    func isWhere(_ other: CGRect) -> Bool {
        abs(minX - other.minX) < 0.5 && abs(minY - other.minY) < 0.5
            && abs(width - other.width) < 0.5 && abs(height - other.height) < 0.5
    }
}
