//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import CoreGraphics
import Foundation

/// Where a shelf's books stand once broken into rows, and where the bracket under each run of them goes.
///
/// A value rather than a view's private working, because three things ask it the same question: a list
/// needs a card's height before the card exists, the card places its books from it, and a bracket has to
/// know which books landed on which row and how wide they came out.
///
/// It counts in one space whose origin is the shelf's top left. Every book stands on the floor of its
/// own row, so one shorter than the tallest keeps its feet down and leaves its room above.
public struct ShelfLayout {
    /// One thing to stand on the shelf, as the layout is handed it.
    public struct Tile: Identifiable, Equatable {
        public let id: String
        /// The run it belongs to, where it belongs to one.
        public let run: String?
        public let width: CGFloat
        /// How tall this one stands, which may be less than the slot it stands in.
        public let height: CGFloat

        public init(id: String, run: String? = nil, width: CGFloat, height: CGFloat) {
            self.id = id
            self.run = run
            self.width = width
            self.height = height
        }
    }

    /// Where one of them ended up.
    public struct Placed: Identifiable, Equatable {
        public let tile: Tile
        public let frame: CGRect
        public let row: Int

        public var id: String { tile.id }
    }

    /// The line under one stretch of a row, and whether the run it belongs to begins or ends there.
    public struct Bracket: Identifiable, Equatable {
        public let run: String
        public let frame: CGRect
        public let opens: Bool
        public let closes: Bool
        public let row: Int

        public var id: String { "\(run)|\(row)|\(frame.minX)" }
    }

    public let placed: [Placed]
    public let brackets: [Bracket]
    /// What the whole shelf comes to, brackets and the gaps between rows included.
    public let height: CGFloat

    public init(tiles: [Tile], slot: CGFloat, across available: CGFloat, gutter: CGFloat) {
        let rows = Self.broken(tiles, across: available, gutter: gutter)
        let step = slot + Self.bracketGap + Self.bracketHeight + Self.rowGap
        var placed: [Placed] = []
        var brackets: [Bracket] = []

        for (index, row) in rows.enumerated() {
            let top = CGFloat(index) * step
            var x: CGFloat = 0

            for tile in row {
                let frame = CGRect(x: x, y: top + slot - tile.height, width: tile.width, height: tile.height)

                placed.append(Placed(tile: tile, frame: frame, row: index))
                x += tile.width + gutter
            }

            brackets += Self.brackets(of: row, in: tiles, row: index, top: top + slot + Self.bracketGap, gutter: gutter)
        }

        self.placed = placed
        self.brackets = brackets
        height = rows.isEmpty ? 0 : CGFloat(rows.count) * step - Self.rowGap
    }

    public func frame(of id: String) -> CGRect? { placed.first { $0.id == id }?.frame }

    /// The books of each row, broken where the next one would not fit. One too wide for the whole
    /// shelf takes a row of its own rather than none.
    private static func broken(_ tiles: [Tile], across available: CGFloat, gutter: CGFloat) -> [[Tile]] {
        var rows: [[Tile]] = []
        var row: [Tile] = []
        var taken: CGFloat = 0

        for tile in tiles {
            let needed = row.isEmpty ? tile.width : tile.width + gutter

            if taken + needed > available, !row.isEmpty {
                rows.append(row)
                row = []
                taken = 0
            }

            row.append(tile)
            taken += row.count == 1 ? tile.width : tile.width + gutter
        }

        if !row.isEmpty { rows.append(row) }

        return rows
    }

    /// One row's stretches of a single run, each with its own line. A run carrying on onto the next row
    /// is left open at that end, so an unclosed end reads as "continues".
    private static func brackets(
        of row: [Tile],
        in tiles: [Tile],
        row index: Int,
        top: CGFloat,
        gutter: CGFloat
    ) -> [Bracket] {
        var brackets: [Bracket] = []
        var gathered: [Tile] = []
        var x: CGFloat = 0
        var start: CGFloat = 0

        func close() {
            defer { gathered = [] }

            guard let first = gathered.first, let last = gathered.last, let run = first.run else { return }

            brackets.append(Bracket(
                run: run,
                frame: CGRect(
                    x: start,
                    y: top,
                    width: gathered.map(\.width).reduce(0, +) + gutter * CGFloat(gathered.count - 1),
                    height: bracketHeight
                ),
                opens: tiles.first { $0.run == run }?.id == first.id,
                closes: tiles.last { $0.run == run }?.id == last.id,
                row: index
            ))
        }

        for tile in row {
            if tile.run != gathered.first?.run {
                close()
                start = x
            }

            gathered.append(tile)
            x += tile.width + gutter
        }

        close()

        return brackets
    }

    /// The gap between a row of books and the line under it, how deep that line's band is, and the gap
    /// from there to the next row.
    private static let bracketGap = Design.Space.extraSmall
    private static let bracketHeight = Design.Space.large
    private static let rowGap = Design.Space.medium
}
