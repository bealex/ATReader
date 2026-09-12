//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import DesignSystem
import SwiftUI

/// Where the reader is in a book, as a cover shows it: a line along the top edge as far as they've
/// read, and a bookmark standing at its end.
///
/// Only a book being read or still being written carries one, and a finished book for a day after the
/// reader got to its end.
struct ReadingMark: Hashable {
    enum Kind: Hashable {
        /// Part way through, in the ribbon's red with the percentage on it.
        case reading
        /// Read to the end of a finished book, in green with a tick.
        case read
        /// Waiting on the author, in grey with a pencil: nothing read yet, or everything there is.
        case waiting
    }

    let kind: Kind
    /// How far along the top edge the line runs and the bookmark stands, `0…1`.
    let reached: Double

    /// The mark for this book, or nothing where it carries none. `showsProgress` off leaves only what
    /// the book says about itself, for a list where the reader's own progress isn't the point.
    init?(_ work: Book, showsProgress: Bool = true, at now: Date = .now) {
        let progress = showsProgress ? min(1, max(0, work.readingProgress ?? 0)) : 0
        let isReadToTheEnd = showsProgress && work.isReadToTheEnd

        if progress > 0, !isReadToTheEnd {
            self.init(kind: .reading, reached: progress)
        } else if work.isOngoing {
            self.init(kind: .waiting, reached: isReadToTheEnd ? 1 : 0)
        } else if isReadToTheEnd, work.isJustRead(at: now) {
            self.init(kind: .read, reached: 1)
        } else {
            return nil
        }
    }

    private init(kind: Kind, reached: Double) {
        self.kind = kind
        self.reached = reached
    }

    var face: BookmarkMark.Face {
        switch kind {
            // Never 100 while there is anything left, and never 0 once a page has been turned.
            case .reading: .figure(min(99, max(1, Int(reached * 100))))
            case .read: .glyph("checkmark")
            case .waiting: .glyph("pencil")
        }
    }

    var tint: Color {
        switch kind {
            case .reading: BookmarkMark.reading
            case .read: BookmarkMark.read
            case .waiting: BookmarkMark.waiting
        }
    }
}
