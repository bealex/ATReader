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
    /// Which cover shapes these were worked out from, and which written-down ones.
    private static var version = -1
    private static var kept = -1

    static func shape(of work: Book) -> Shape {
        if version != CoverShapes.version || kept != KeptShapes.version {
            shapes.removeAll(keepingCapacity: true)
            version = CoverShapes.version
            kept = KeptShapes.version
        }

        if let known = shapes[work.id], known.coverURL == work.coverURL { return known }

        // The picture this run has decoded, and otherwise what an earlier run wrote down. A cover kept
        // on the device is named by a path that changes with every install, so the picture is no help
        // until it has been read again, and the book's own record is.
        let written = KeptShapes.shape(of: work.id)
        let shape = Shape(
            coverURL: work.coverURL,
            cover: work.coverURL.flatMap(CoverShapes.aspect(for:)) ?? written?.cover.map { CGFloat($0) },
            length: Shelf.lengthShare(of: work) ?? written?.spine
        )

        shapes[work.id] = shape
        KeptShapes.remember(BookShape(cover: shape.cover.map { Double($0) }, spine: shape.length), for: work.id)
        return shape
    }
}
