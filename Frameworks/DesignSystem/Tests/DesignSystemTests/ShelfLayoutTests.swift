//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import CoreGraphics
import Testing

@testable import DesignSystem

/// Where a shelf puts its books, which nothing on screen can be asked about until it is drawn.
struct ShelfLayoutTests {
    private func tile(_ id: String, run: String? = nil, width: CGFloat = 30, height: CGFloat = 90) -> ShelfLayout.Tile {
        ShelfLayout.Tile(id: id, run: run, width: width, height: height)
    }

    private func layout(_ tiles: [ShelfLayout.Tile], across: CGFloat = 100) -> ShelfLayout {
        ShelfLayout(tiles: tiles, slot: 90, across: across, gutter: 6)
    }

    @Test
    func standsBooksSideBySideWithAGutterBetweenThem() {
        let shelf = layout([ tile("a"), tile("b") ])

        #expect(shelf.frame(of: "a")?.minX == 0)
        #expect(shelf.frame(of: "b")?.minX == 36)
        #expect(shelf.placed.allSatisfy { $0.row == 0 })
    }

    @Test
    func breaksTheRowWhereTheNextBookWouldNotFit() {
        let shelf = layout([ tile("a"), tile("b"), tile("c") ])

        #expect(shelf.placed.map(\.row) == [ 0, 0, 1 ])
        #expect(shelf.frame(of: "c")?.minX == 0)
        #expect(shelf.frame(of: "c")?.minY ?? 0 > shelf.frame(of: "a")?.minY ?? 0)
    }

    @Test
    func givesABookTooWideForTheShelfARowOfItsOwn() {
        let shelf = layout([ tile("wide", width: 300) ])

        #expect(shelf.placed.count == 1)
        #expect(shelf.frame(of: "wide")?.width == 300)
    }

    @Test
    func standsAShortBookOnTheFloorOfItsRow() {
        let shelf = layout([ tile("tall"), tile("short", height: 60) ])

        let tall = shelf.frame(of: "tall")
        let short = shelf.frame(of: "short")

        #expect(tall?.maxY == short?.maxY)
        #expect(short?.minY ?? 0 > tall?.minY ?? 0)
    }

    @Test
    func drawsOneBracketPerRunAndSpansTheBooksInIt() {
        let shelf = layout([ tile("a", run: "one"), tile("b", run: "one") ], across: 200)

        #expect(shelf.brackets.count == 1)

        let bracket = shelf.brackets.first

        #expect(bracket?.frame.minX == 0)
        #expect(bracket?.frame.width == 66)
        #expect(bracket?.opens == true)
        #expect(bracket?.closes == true)
    }

    @Test
    func leavesARunOpenWhereItCarriesOnOntoTheNextRow() {
        let shelf = layout([ tile("a", run: "one"), tile("b", run: "one"), tile("c", run: "one") ])

        #expect(shelf.brackets.count == 2)
        #expect(shelf.brackets.first?.opens == true)
        #expect(shelf.brackets.first?.closes == false)
        #expect(shelf.brackets.last?.opens == false)
        #expect(shelf.brackets.last?.closes == true)
    }

    @Test
    func holdsNoBracketOverABookBelongingToNoRun() {
        let shelf = layout([ tile("a"), tile("b") ])

        #expect(shelf.brackets.isEmpty)
    }

    @Test
    func startsEachRunsBracketWhereItsOwnBooksStart() {
        let shelf = layout([ tile("a", run: "one"), tile("b", run: "two") ], across: 200)

        #expect(shelf.brackets.count == 2)
        #expect(shelf.brackets.first?.frame.minX == 0)
        #expect(shelf.brackets.last?.frame.minX == 36)
    }

    @Test
    func measuresItselfByItsBoardAndItsRows() {
        let one = layout([ tile("a") ])
        let two = layout([ tile("a"), tile("b"), tile("c") ])

        // The board across the top, 6, then a row: headroom 9, the slot 90, and the plank under it, 24.
        #expect(one.height == 129)
        #expect(two.height == 252)
    }

    @Test
    func standsEveryRowOnItsPlank() {
        let shelf = layout([ tile("a"), tile("b"), tile("c") ])

        // The board, the headroom and the slot; the second row one row's depth, 123, further down.
        #expect(shelf.frame(of: "a")?.maxY == 105)
        #expect(shelf.frame(of: "c")?.maxY == 228)
    }

    @Test
    func setsABracketOnTheFrontOfThePlankUnderItsRun() {
        let shelf = layout([ tile("a", run: "one") ])
        let floor: CGFloat = 6 + 9 + 90

        #expect(shelf.brackets.first?.frame.minY ?? 0 >= floor)
        #expect(shelf.brackets.first?.frame.maxY ?? .infinity <= floor + 24)
    }

    @Test
    func measuresAnEmptyShelfAsNothing() {
        #expect(layout([]).height == 0)
    }
}
