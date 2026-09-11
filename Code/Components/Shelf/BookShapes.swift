//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import UIKit

/// Each book's cover shape and spine thickness, worked out once and kept by book.
///
/// A shelf asks about every book on it each time it is laid out, and the list lays every card out to
/// learn how tall it stands. Asked by cover address, each of those questions hashes a string.
@MainActor
enum BookShapes {
    struct Shape {
        let coverURL: URL?
        /// How many times taller than wide the cover is, where it has been seen.
        let cover: CGFloat?
        /// Where the book's length falls between the shortest and the longest a spine is measured for.
        let length: Double?
    }

    private static var shapes: [Int: Shape] = [:]
    /// Which cover shapes these were worked out from.
    private static var version = -1

    static func shape(of work: Book) -> Shape {
        if version != CoverShapes.version {
            shapes.removeAll(keepingCapacity: true)
            version = CoverShapes.version
        }

        if let known = shapes[work.id], known.coverURL == work.coverURL { return known }

        let shape = Shape(
            coverURL: work.coverURL,
            cover: work.coverURL.flatMap(CoverShapes.aspect(for:)),
            length: Shelf.lengthShare(of: work)
        )

        shapes[work.id] = shape
        return shape
    }
}
