//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookRenderer
import Foundation

extension ReaderScreen.Model {
    /// One place in the book the words stand.
    struct Found: Equatable, Identifiable {
        let chapterId: Int
        /// Where it begins in the chapter, counted the way a reading position is.
        let offset: Int

        var id: String { "\(chapterId).\(offset)" }
    }

    /// A chapter folded for searching, counted the way a reading position is.
    ///
    /// The chapter's own blocks rather than the page's text: they carry no soft hyphens, which is
    /// what a stored position counts them as too, and a chapter nothing has laid out yet has them
    /// all the same.
    func findableText(of chapterId: Int) async -> BookSearch.Folded? {
        guard let content = await content(for: chapterId) else { return nil }

        return BookSearch.fold(content.paragraphs.map(\.text).joined(separator: "\n"))
    }

    /// Where a passage found by searching stands in a chapter now laid out.
    ///
    /// A chapter is searched without the heading the reader sets above it and laid out with one, so
    /// the two counts differ by a fixed amount, and the reading nearest the offset is the passage
    /// that was found.
    func place(of words: String, near: Int, in built: ChapterLayout) -> Range<Int>? {
        guard let chapter = folded(built.chapterId) else { return nil }

        return BookSearch.matches(of: words, in: chapter)
            .min { abs($0.lowerBound - near) < abs($1.lowerBound - near) }
    }

    /// Where the words the reader was taken to stand on a page, for painting under them.
    ///
    /// Only the place they were taken to. The others are elsewhere in the book, and painting every
    /// saying of a word on the page would leave it looking marked up rather than searched.
    func foundRects(onPage index: Int) -> [CGRect] {
        guard let place = foundPlace, case let .text(pieces) = page(at: index) else { return [] }

        return
            pieces
            .filter { $0.layout.chapterId == place.chapterId }
            .flatMap { $0.layout.rects(of: $0.layout.laidOutRange(of: place.range), onPage: $0.page) }
    }
}
