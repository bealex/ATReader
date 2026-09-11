//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import Testing

@testable import BookKit

/// The two ways a series writes its own numbering, and what happens when it writes none.
///
/// Every title here is invented. The shapes are what matter: a run of words at one end of the title
/// with a figure somewhere in it.
struct SeriesNumberingTests {
    private func books(_ titles: [String]) -> [Book] {
        titles.enumerated().map { index, title in
            Book(id: index + 1, title: title, authorLine: "Author Name", coverURL: nil, annotation: nil)
        }
    }

    @Test
    func readsAFigureHeldAtTheBackOfEveryTitle() throws {
        let reading = try #require(
            SeriesNumbering.read(books([
                "Tin Garden (Ember-4)",
                "Spindle and Ash (Ember-3)",
                "Quiet Harbour (Ember-1)",
            ]))
        )

        #expect(reading.books.map(\.number) == [ 4, 3, 1 ])
        #expect(reading.books.map(\.title) == [ "Tin Garden", "Spindle and Ash", "Quiet Harbour" ])
        #expect(reading.missing == [ 2 ])
    }

    @Test
    func readsAFigureHeldAtTheFrontOfEveryTitle() throws {
        let reading = try #require(
            SeriesNumbering.read(books([
                "Salt Road 3. Long Winter",
                "Salt Road 2. The Crossing",
                "Salt Road. First Light",
            ]))
        )

        #expect(reading.books.map(\.number) == [ 3, 2, 1 ])
        #expect(reading.books.map(\.title) == [ "Long Winter", "The Crossing", "First Light" ])
        #expect(reading.missing.isEmpty)
    }

    /// A title carrying the shared words and no figure is the first volume, which is how the one book
    /// published before anyone thought to number them gets its place.
    @Test
    func countsATitleWithNoFigureAsTheFirst() throws {
        let reading = try #require(
            SeriesNumbering.read(books([
                "Salt Road 2. The Crossing",
                "Salt Road. First Light",
            ]))
        )

        #expect(reading.books.map(\.number) == [ 2, 1 ])
    }

    @Test
    func namesEveryVolumeNothingOnTheShelfAccountsFor() throws {
        let reading = try #require(
            SeriesNumbering.read(books([
                "Tin Garden (Ember-6)",
                "Quiet Harbour (Ember-2)",
            ]))
        )

        #expect(reading.missing == [ 3, 4, 5 ])
    }

    /// A figure every title shares is part of the series' name; the one that changes is the volume.
    @Test
    func readsPastAFigureInTheSeriesName() throws {
        let reading = try #require(
            SeriesNumbering.read(books([
                "99 Worlds. Harbour",
                "99 Worlds – 2. North",
                "99 Worlds – 3. Ash",
            ]))
        )

        #expect(reading.books.map(\.number) == [ 1, 2, 3 ])
        #expect(reading.books.map(\.title) == [ "Harbour", "North", "Ash" ])
    }

    /// The dash between a series' name and its figure goes with them.
    @Test
    func takesTheNameDashAndFigureOffATitle() {
        #expect(SeriesNumbering.title("99 Worlds – 2. North", in: "99 Worlds", volume: 2) == "North")
    }

    /// What a book states about its volume beats what its title says, book by book.
    @Test
    func aStatedVolumeBeatsTheTitle() throws {
        var held = books([ "Ember 5. Tin Garden", "Ember 6. Frost", "Ember 7. Ash" ])

        held[0].seriesOrder = 1
        held[1].seriesOrder = 0

        let volumes = SeriesNumbering.volumes(of: held, reading: SeriesNumbering.read(held))

        // A stated nought is no volume, so the title's figure stands for that book.
        #expect(volumes == [ 1: 1, 2: 6, 3: 7 ])
    }

    @Test
    func leavesTitlesThatShareNoRunAlone() {
        #expect(SeriesNumbering.read(books([ "Tin Garden", "Spindle and Ash", "Quiet Harbour" ])) == nil)
    }

    /// Words repeat across a series all the time without numbering it. Without a figure there is
    /// nothing to read, and taking the words off would only lose the reader the title.
    @Test
    func leavesASharedRunWithNoFigureAlone() {
        #expect(SeriesNumbering.read(books([ "The Long Road Home", "The Long Road Back" ])) == nil)
    }

    @Test
    func leavesASeriesOfOneAlone() {
        #expect(SeriesNumbering.read(books([ "Tin Garden (Ember-4)" ])) == nil)
    }

    /// Removing the run must never leave a row with nothing on it.
    @Test
    func keepsTheWholeTitleWhereTheRunIsAllThereIs() throws {
        let reading = try #require(SeriesNumbering.read(books([ "Ember 2", "Ember 1" ])))

        #expect(reading.books.allSatisfy { !$0.title.isEmpty })
    }

    // MARK: - The aside a series writes into a title

    /// One library writes the series into a title where the other leaves it out, and half a series
    /// carrying the aside is no run to read. The aside is not part of the book's name either way.
    @Test
    func takesTheSeriesAsideOffATitle() {
        #expect(SeriesNumbering.title("Tin Garden (Ember-4)", in: "Ember") == "Tin Garden")
    }

    /// Anything else in brackets is part of what the book is called.
    @Test
    func keepsAnAsideThatIsNotTheSeries() {
        #expect(SeriesNumbering.title("Tin Garden (a collection)", in: "Ember") == "Tin Garden (a collection)")
    }

    /// A title that is nothing but its aside keeps it: there would be nothing left to call it.
    @Test
    func keepsATitleThatIsOnlyItsAside() {
        #expect(SeriesNumbering.title("(Ember-4)", in: "Ember") == "(Ember-4)")
    }

    /// The series' name at the front of a title, and the figure it carried, belong to the series.
    @Test
    func takesTheSeriesNameOffTheFrontOfATitle() {
        #expect(SeriesNumbering.title("Ember 3. Tin Garden", in: "Ember") == "Tin Garden")
    }

    /// A book whose title is its series' name is called that, so nothing is taken.
    @Test
    func keepsATitleThatIsOnlyTheSeriesName() {
        #expect(SeriesNumbering.title("Ember", in: "Ember") == "Ember")
    }

    @Test
    func leavesATitleAloneWithoutASeries() {
        #expect(SeriesNumbering.title("Tin Garden (Ember-4)", in: nil) == "Tin Garden (Ember-4)")
    }

    /// A title that is the series' name and its index is called by the name.
    @Test
    func takesTheIndexOffATitleThatIsOnlyTheSeriesName() {
        #expect(SeriesNumbering.title("Ember (Ember-1)", in: "Ember", volume: 1) == "Ember")
        #expect(SeriesNumbering.title("Ember. Book 8", in: "Ember", volume: 8) == "Ember")
    }

    // MARK: - Volume words

    /// "Book 4" where the book is volume four is the series' index.
    @Test
    func takesAVolumeWordStatingTheBooksOwnVolume() {
        #expect(SeriesNumbering.title("Ember. Book 4. Tin Garden", in: "Ember", volume: 4) == "Tin Garden")
        #expect(SeriesNumbering.title("Ember, Part 2", in: "Ember", volume: 2) == "Ember")
    }

    /// Any other figure numbers the book within a smaller cycle, which the shelf writes shorter.
    @Test
    func writesAnyOtherVolumeWordAsAPart() {
        #expect(SeriesNumbering.title("Tin Garden. Book 2", in: "Ember", volume: 5) == "Tin Garden /2")
        #expect(SeriesNumbering.title("Tin Garden (book 1)", in: "Ember", volume: 7) == "Tin Garden /1")
        #expect(SeriesNumbering.title("Tin Garden. Part 1. Frost", in: "Ember", volume: nil) == "Tin Garden /1. Frost")
    }

    /// A figure after the word is what makes it a volume.
    @Test
    func keepsAVolumeWordWithNoFigure() {
        #expect(SeriesNumbering.title("The Book of Ash", in: "Ember", volume: 2) == "The Book of Ash")
    }

    // MARK: - The series' name at the front

    /// A colon after the series' name starts the book's own name.
    @Test
    func keepsTheSeriesNameBeforeAColon() {
        #expect(SeriesNumbering.title("Ember: Tin Garden", in: "Ember", volume: 1) == "Ember: Tin Garden")
        #expect(SeriesNumbering.title("Ember: Tin Garden. Book 1", in: "Ember", volume: 6) == "Ember: Tin Garden /1")
    }

    /// Where the rest of the series numbers its name, the one volume without a figure loses it too.
    @Test
    func takesTheNameOffEveryTitleWhereTheSeriesNumbersIt() throws {
        let books = [ "Ember: Tin Garden", "Ember 2: Frost", "Ember 3: Ash" ].enumerated().map { index, title in
            Book(
                id: index + 1,
                title: title,
                authorLine: "Author Name",
                coverURL: nil,
                annotation: nil,
                seriesTitle: "Ember",
                seriesOrder: index + 1
            )
        }
        let reading = try #require(SeriesNumbering.read(books))

        #expect(reading.books.map(\.title) == [ "Tin Garden", "Frost", "Ash" ])
    }

    /// A figure between the name and the colon is the series' own numbering.
    @Test
    func takesTheSeriesNameAndFigureBeforeAColon() {
        #expect(SeriesNumbering.title("Ember 2: Tin Garden", in: "Ember", volume: 2) == "Tin Garden")
    }
}
