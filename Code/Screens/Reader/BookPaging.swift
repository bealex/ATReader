//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// Where a page falls in the whole book rather than in its own chapter.
///
/// Worked out once a pass rather than for every page drawn, since a book runs to hundreds of pages and
/// the answer only changes when something is measured. The title page stands in front of everything and
/// is page one, so every chapter's own paging is one further in than the paginator counted it.
struct BookPaging: Equatable {
    /// Where each chapter's first page falls in the book, counting from one.
    let firstPages: [Int: Int]
    /// How many pages each chapter ran to when it was measured.
    let chapterPages: [Int: Int]
    /// How long the book ran to when it was measured, the title page included.
    let length: Int

    static let nothing = BookPaging(firstPages: [:], chapterPages: [:], length: 0)

    /// Where one of a chapter's own pages falls in the book, both counted from one.
    ///
    /// A chapter that runs on begins on the page the one before it ended on, and that page belongs to
    /// both: asked about either of them it gives the same answer.
    func page(of chapter: Int, within page: Int) -> Int? {
        guard let first = firstPages[chapter] else { return nil }

        return first + page - 1
    }

    /// How long the book is, given what one of its chapters measures now.
    ///
    /// The length is the sum of what an earlier pass measured chapter by chapter, and a chapter that has
    /// grown since is the one the reader is most likely to be in: a new chapter arriving from the
    /// service carries the end of the last one with it. Left uncorrected, the reader is walked past an
    /// end that has not caught up.
    func length(with chapter: Int, measuring pages: Int) -> Int {
        guard let was = chapterPages[chapter] else { return length }

        return length + pages - was
    }
}
