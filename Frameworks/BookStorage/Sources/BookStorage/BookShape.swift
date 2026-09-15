//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// What shape a book stands in: how tall its cover is against its width, and how thick its spine is.
///
/// Either may be unknown. A cover's shape is learned from its picture, a spine's from the book's own
/// length, and neither waits for the other.
public struct BookShape: Equatable, Sendable {
    /// How many times taller than wide the cover is.
    public var cover: Double?
    /// Where the book's length falls between the shortest and the longest a spine is measured for.
    public var spine: Double?

    public init(cover: Double? = nil, spine: Double? = nil) {
        self.cover = cover
        self.spine = spine
    }
}

/// Every book's shape, kept by the book and read back as the app comes up.
///
/// Filed under the book rather than under the address of its picture. A cover held on this device is
/// named by a path through the app's container, and that path changes with every install, so anything
/// filed under it is lost the next time the app is built. A shelf that has lost a book's shape lays it
/// out at a guess and cuts its picture to the slot it guessed, which is what a reader sees.
@MainActor
public enum KeptShapes {
    /// Held here as well as in the store, because a shelf asks about every book on it while it is
    /// laying them out, and the store answers across an actor hop it cannot wait for.
    private static var shapes: [Int: BookShape] = [:]

    /// Moves when the written-down shapes are read back, for whatever keeps what it worked out from
    /// them. Learning one while the app runs doesn't move it: whoever writes a shape here has just
    /// worked it out and needs nothing thrown away.
    public private(set) static var version = 0

    public static func shape(of workId: Int) -> BookShape? { shapes[workId] }

    /// Reads back what earlier runs measured. Once, as the app comes up.
    public static func load(from store: SQLiteBookStore = .shared) async {
        shapes = await store.bookShapes()
        version += 1
    }

    /// Keeps whichever half is given, where it is news. The other half stands.
    public static func remember(_ shape: BookShape, for workId: Int) {
        var kept = shapes[workId] ?? BookShape()

        if let cover = shape.cover { kept.cover = cover }
        if let spine = shape.spine { kept.spine = spine }

        guard kept != shapes[workId] else { return }

        shapes[workId] = kept
        Task { await SQLiteBookStore.shared.store(shape: shape, workId: workId) }
    }
}
