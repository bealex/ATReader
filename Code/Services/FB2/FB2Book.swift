//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// A FictionBook 2 file, parsed into the shape the reader already works in.
///
/// Sections carry `<p>` markup rather than a tree of their own, because that is what `ChapterHTML`
/// reads and what a chapter body arrives as from the service. Everything downstream of a chapter body
/// then works on a local book without knowing it is one.
struct FB2Book: Sendable {
    /// One chapter: a top-level section of the book's main body.
    struct Section: Sendable {
        let title: String?
        let html: String
        /// Characters of text, which is what a book's reading progress is weighed in.
        let textLength: Int
    }

    let title: String
    let authors: [String]
    let annotation: String?
    /// The language tag the file declares, which picks the hyphenation dictionary.
    let language: String?
    let series: String?
    let seriesOrder: Int?
    /// The cover image as the file embeds it, already decoded from base64.
    let cover: Data?
    let sections: [Section]
    /// The `document-info/id` the file carries, where it has one. Two files with the same identifier
    /// are two editions of one book.
    let identifier: String?

    /// What this book is filed under, so a corrected file replaces the book it corrects.
    ///
    /// The file's own identifier where it has one, and the title and author where it doesn't. Hashing
    /// the bytes instead would file every corrected copy as a new book.
    var fingerprint: String {
        identifier.map { "fb2:id:\($0)" } ?? "fb2:name:\(title)|\(authors.joined(separator: ","))"
    }

    var authorLine: String {
        authors.isEmpty ? String(localized: "Unknown author") : authors.joined(separator: ", ")
    }
}

enum FB2Error: LocalizedError {
    case unreadable
    case malformed(String?)
    case notABook

    var errorDescription: String? {
        switch self {
            case .unreadable: String(localized: "That file couldn’t be read.")
            case let .malformed(detail):
                detail.map { String(localized: "That file isn’t valid FB2: \($0)") }
                    ?? String(localized: "That file isn’t valid FB2.")
            case .notABook: String(localized: "That FB2 file has no text in it.")
        }
    }
}
