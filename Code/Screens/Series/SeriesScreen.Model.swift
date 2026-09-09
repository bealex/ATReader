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
            var seen: Set<String> = []

            return
                books
                .flatMap { $0.authorLine.split(separator: ",") }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .compactMap { seen.insert($0.lowercased()).inserted ? $0 : nil }
        }

        /// This book's volume: what it states about itself, and failing that what its title says.
        ///
        /// A file carries the volume its publisher gave it, which is worth more than a figure read off
        /// a title: two parts of one volume are both numbered four, and no reading of their names can
        /// say so.
        func number(of work: Book) -> Int? {
            guard !titlesTellThemApart, statesVolumes else { return readOff(work) }

            return work.seriesOrder
        }

        private func readOff(_ work: Book) -> Int? {
            numbering?.books.first { $0.book.id == work.id }?.number
        }

        /// True where the titles give every book here a volume of its own, which is the numbering to
        /// trust: what two services state about one series comes out with repeats in it often enough.
        private var titlesTellThemApart: Bool {
            guard let numbering else { return false }

            return Set(numbering.books.map(\.number)).count == books.count
        }

        /// True where every book here states a volume, and they do not all state the same one.
        private var statesVolumes: Bool {
            let stated = books.compactMap(\.seriesOrder)

            return stated.count == books.count && Set(stated).count > 1
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
