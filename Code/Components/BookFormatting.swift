//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Foundation
import SwiftUI

/// Shared number and date wording, so every screen phrases a book's size the same way.
enum BookFormatting {
    static func likes(_ count: Int?) -> String? {
        guard let count, count > 0 else { return nil }

        return count.formatted(.number.notation(.compactName))
    }

    static func progress(_ value: Double?) -> String? {
        guard let value, value > 0 else { return nil }

        return (value).formatted(.percent.precision(.fractionLength(0)))
    }

    /// When this copy last moved, in the words that fit where it came from: the service updates a
    /// book, Litres hands one over, and a file is put on the device by the reader.
    static func moved(_ date: Date?, origin: CoverOrigin?) -> String? {
        guard let date else { return nil }

        let when = date.formatted(.relative(presentation: .named))

        return switch origin {
            case .litres: String(localized: "Downloaded \(when)")
            case .file: String(localized: "Uploaded \(when)")
            case .service, nil: String(localized: "Updated \(when)")
        }
    }
}

/// What a shelf is called and what it looks like, which is the app's wording rather than the service's.
extension BookShelf {
    var title: String {
        switch self {
            case .none: String(localized: "Not in library")
            case .reading: String(localized: "Reading")
            case .saved: String(localized: "Saved")
            case .finished: String(localized: "Finished")
            case .disliked: String(localized: "Disliked")
        }
    }

    var systemImage: String {
        switch self {
            case .none: "book"
            case .reading: "book.fill"
            case .saved: "bookmark.fill"
            case .finished: "checkmark.circle.fill"
            case .disliked: "hand.thumbsdown.fill"
        }
    }
}

/// What a chapter is called in a list. A chapter the author left unnamed is called by its number, which
/// is the app's wording: the service has no say in it.
extension BookChapter {
    var displayTitle: String {
        guard
            let title,
            !title.isEmpty
        else {
            return String(localized: "Chapter \((sortOrder ?? 0) + 1)")
        }

        return title
    }

    /// How deep this stands. A book that said nothing about its own structure is all one level.
    var contentsLevel: Int { max(1, level ?? 1) }
}

extension [BookChapter] {
    /// What each of these is called in a contents list.
    ///
    /// A piece the book named keeps its name. One it did not is called by what it is and which one it
    /// is: the pieces a chapter is cut into are counted within that chapter rather than through the
    /// whole book, so the first under every heading is the first.
    func contentsNames() -> [String] {
        var counted = 0

        return map { chapter in
            if let title = chapter.title, !title.isEmpty {
                counted = 0
                return title
            }

            guard
                chapter.contentsLevel > 1
            else {
                counted = 0
                return chapter.displayTitle
            }

            counted += 1
            return String(localized: "Piece \(counted)")
        }
    }
}
