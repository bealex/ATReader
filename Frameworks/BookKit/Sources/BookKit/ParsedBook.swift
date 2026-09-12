//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// A book as a parser made it, before the store has given it a number.
///
/// Sections carry the same markup a chapter arrives in from the service on purpose, so everything
/// downstream of a chapter body works on a book from a file without knowing it is one.
public struct ParsedBook: Sendable {
    /// One chapter: a top-level section of the book's main body.
    public struct Section: Sendable {
        public let title: String?
        public let html: String
        /// Characters of text, which is what a book's reading progress is weighed in.
        public let textLength: Int
        /// How deep this stands in the book: one for a part or a chapter the file names outright, more
        /// for anything marked inside one. What the contents indents by.
        public let level: Int

        public init(title: String?, html: String, textLength: Int, level: Int = 1) {
            self.title = title
            self.html = html
            self.textLength = textLength
            self.level = level
        }
    }

    public let title: String
    public let authors: [String]
    public let annotation: String?
    /// The language tag the file declares, which picks the hyphenation dictionary.
    public let language: String?
    public let series: String?
    public let seriesOrder: Int?
    /// The cover image as the file embeds it, already decoded.
    public let cover: Data?
    /// Every picture the text points at, by the name its markup gives it.
    public let images: [String: Data]
    public let sections: [Section]
    /// The identifier the file carries, where it has one. Two files with the same identifier are two
    /// editions of one book.
    public let identifier: String?

    public init(
        title: String,
        authors: [String],
        annotation: String?,
        language: String?,
        series: String?,
        seriesOrder: Int?,
        cover: Data?,
        images: [String: Data],
        sections: [Section],
        identifier: String?
    ) {
        self.title = title
        self.authors = authors
        self.annotation = annotation
        self.language = language
        self.series = series
        self.seriesOrder = seriesOrder
        self.cover = cover
        self.images = images
        self.sections = sections
        self.identifier = identifier
    }

    /// What this book is filed under, so a corrected file replaces the book it corrects.
    ///
    /// The file's own identifier and the book's name, rather than either alone. Hashing the bytes would
    /// file every corrected copy as a new book, and the identifier by itself trusts a field that some
    /// files get wrong: filing two different books as one loses the text of the first, where filing one
    /// book twice leaves a duplicate the reader can see and delete.
    public var fingerprint: String {
        let name = "\(title)|\(authors.joined(separator: ","))"

        return identifier.map { "fb2:id:\($0)|\(name)" } ?? "fb2:name:\(name)"
    }

    public var authorLine: String {
        authors.isEmpty ? String(localized: "Unknown author", bundle: .module) : authors.joined(separator: ", ")
    }
}

/// A book as read, with the bytes worth keeping alongside it.
public struct ReadBook: Sendable {
    public let book: ParsedBook
    /// The book's own text, which is not the file it arrived in where that file was an archive. This
    /// is what gets kept, so a book can be read again by a parser that has since learned something.
    public let source: Data

    public init(book: ParsedBook, source: Data) {
        self.book = book
        self.source = source
    }
}

/// A file format this app can read a book out of.
public protocol BookFormat: Sendable {
    /// The bytes decide, not the name.
    func canRead(_ data: Data) -> Bool

    func read(_ data: Data) async throws -> ReadBook
}
