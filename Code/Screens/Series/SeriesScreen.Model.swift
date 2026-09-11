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

        /// Everyone this series is by, each named once, in the order they first appear.
        ///
        /// Every name rather than the one most books carry: a series can be written by two people, or
        /// taken over by another, or held together out of two writers' runs by the reader. A card can
        /// afford one name; a screen about the series itself should say who wrote it.
        var authors: [String] {
            let names =
                books
                .flatMap { $0.authorLine.split(separator: ",") }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            // Two spellings of one name are one writer here as they are on the shelf.
            let filed = WriterNames.filed(names)
            var seen: Set<String> = []

            return names.compactMap { name in
                let writer = filed[name] ?? name

                return seen.insert(writer.lowercased()).inserted ? writer : nil
            }
        }

        /// This book's volume: what it states about itself, and failing that what its title says.
        func number(of work: Book) -> Int? {
            SeriesNumbering.volumes(of: books, reading: numbering)[work.id]
        }

        /// The title with the series' own repeated words taken off it.
        func title(of work: Book) -> String {
            numbering?.books.first { $0.book.id == work.id }?.title
                ?? SeriesNumbering.title(work.title, in: series, volume: work.seriesOrder)
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
            await store.store(order: books.map(\.id), series: series)
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
