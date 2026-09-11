//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import DesignSystem
import SwiftUI

/// How a series stands on its shelf.
enum Shelf {
    /// The gap between books. The same figure decides how many covers go in a row, so both readings
    /// of it come from here rather than from two places that have to be kept in step.
    static let gutter = Design.Space.small

    /// What a book is taken to look like before anything has seen its cover.
    static let unknownShape: CGFloat = 1.5

    /// How thick a book stands: its own length, between a floor that leaves room for the writing and a
    /// ceiling that stops one long book crowding out the covers beside it.
    ///
    /// A shelf of one width says every book is the same size, which no shelf of real books is.
    static func spineWidth(of work: Book, cover: CGFloat = Design.Size.gridCover) -> CGFloat {
        spineWidth(share: lengthShare(of: work), cover: cover)
    }

    /// A spine's thickness from where the book's length falls between the shortest and the longest,
    /// `nil` standing for a length nobody knows.
    static func spineWidth(share: Double?, cover: CGFloat) -> CGFloat {
        let thinnest = max(Design.Size.spine, cover * 0.2)
        let thickest = cover * 0.32

        guard let share else { return (thinnest + thickest) / 2 }

        return thinnest + (thickest - thinnest) * share
    }

    /// Where a book's length falls between the shortest and the longest a spine is measured for, from
    /// nought to one.
    static func lengthShare(of work: Book) -> Double? {
        guard let length = work.textLength, length > 0 else { return nil }

        return min(1, max(0, (Double(length) - shortBook) / (longBook - shortBook)))
    }

    /// The lengths a spine is measured between. Below the first every book is as thin as the writing
    /// allows; above the second, as thick as the shelf allows.
    private static let shortBook: Double = 250_000
    private static let longBook: Double = 1_400_000
}

/// One of an author's series, as the shelf needs it.
struct ShelfRun: Identifiable {
    let id: String
    let title: String
    let slots: [SeriesSlot]
}

/// One place in a series: a book the reader holds, or a volume they don't.
enum SeriesSlot: Identifiable {
    case book(Book, number: Int?, title: String, isRead: Bool)
    case missing(Int)

    var id: String {
        switch self {
            case let .book(work, _, _, _): "book:\(work.id)"
            case let .missing(number): "gap:\(number)"
        }
    }
}
