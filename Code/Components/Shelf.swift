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
