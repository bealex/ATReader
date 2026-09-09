//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import Foundation

extension SeriesScreen {
    @Observable @MainActor
    final class Model {
        let series: String

        private(set) var books: [Book] = []
        private(set) var numbering: SeriesNumbering.Reading?
        /// True where the reader put this series together rather than the service naming it.
        private(set) var isArranged = false

        @ObservationIgnored
        private let store: SQLiteBookStore

        init(series: String, store: SQLiteBookStore = .shared) {
            self.series = series
            self.store = store
        }

        var readCount: Int { books.count(where: \.isFinishedReading) }

        /// Who the series is by: the name most of its books carry.
        var author: String? {
            var counted: [String: Int] = [:]
            let names = books.map(\.authorLine).filter { !$0.isEmpty }

            for name in names { counted[name, default: 0] += 1 }

            let most = counted.values.max()

            return names.first { counted[$0] == most }
        }

        /// This book's volume, where the series numbers itself in its titles.
        func number(of work: Book) -> Int? {
            numbering?.books.first { $0.book.id == work.id }?.number
        }

        /// The title with the series' own repeated words taken off it.
        func title(of work: Book) -> String {
            numbering?.books.first { $0.book.id == work.id }?.title
                ?? SeriesNumbering.withoutSeries(work.title, in: series)
        }

        func load() async {
            let held = await store.books().filter { $0.series == series }
            let records = await store.localBooks()
            let arranged = Set(await store.customSeries().values.map(\.series))
            // The same pairing the shelf runs. Reading the store straight showed both copies of every
            // book the shelf had already joined, which is the shelf lying in one of the two places.
            let hashes = records.reduce(into: [Int: String]()) { found, record in
                guard let hash = record.contentHash else { return }

                found[record.workId] = hash
            }
            let one = LibraryScreen.Model.oneOfEach(held, sameText: hashes, arranged: arranged)

            isArranged = arranged.contains(series)
            books = LibraryScreen.Model.ordered(one, arrangedByHand: isArranged)
            numbering = SeriesNumbering.read(books)
        }

        /// Moves books about and files the new order, which is what makes the series the reader's own.
        func move(from picked: IndexSet, to destination: Int) async {
            books.move(fromOffsets: picked, toOffset: destination)
            await store.store(series: series, workIds: books.map(\.id))
            isArranged = true
            BookInbox.shared.libraryChanged()
        }

        /// Gives the books back to whatever the service and the files say they belong to.
        func ungroup() async {
            await store.removeFromCustomSeries(workIds: books.map(\.id))
            BookInbox.shared.libraryChanged()
        }
    }
}
