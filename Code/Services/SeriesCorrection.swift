//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import Foundation

/// The series and volume the reader says one book has, over what its file or the service states.
///
/// Merging books into a series writes the same thing: the name, into each book's own series. So naming a
/// merged series joins it, and naming any other leaves it.
@MainActor
enum SeriesCorrection {
    /// What an editor starts from: the series and volume the book states itself, and what the reader
    /// set over them.
    struct Draft: Equatable, Sendable {
        let ownSeries: String?
        let ownVolume: Int?
        let edit: SQLiteBookStore.SeriesEdit?
    }

    static func draft(for workId: Int, store: SQLiteBookStore = .shared) async -> Draft {
        let own = await store.ownSeries(workId: workId)

        return Draft(ownSeries: own.series, ownVolume: own.volume, edit: await store.seriesEdits()[workId])
    }

    /// Writes what the reader set on a book, or with `nil` gives it back the series and volume it came
    /// with, out of any series it was merged into.
    static func save(_ edit: SQLiteBookStore.SeriesEdit?, for workId: Int, store: SQLiteBookStore = .shared) async {
        await store.store(seriesEdit: edit, workId: workId)
        BookInbox.shared.libraryChanged()
    }

    /// Every series the book's lead writer has among `books`, to pick from rather than type.
    static func writersSeries(of book: Book, among books: [Book]) -> [String] {
        let writer = leadWriter(of: book)
        let series = Set(books.filter { leadWriter(of: $0) == writer }.compactMap(\.series))

        return series.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func leadWriter(of book: Book) -> String {
        String(book.authorLine.split(separator: ",").first ?? "").trimmingCharacters(in: .whitespaces).lowercased()
    }
}
