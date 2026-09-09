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
        #expect(SeriesNumbering.withoutSeries("Tin Garden (Ember-4)", in: "Ember") == "Tin Garden")
    }

    /// Anything else in brackets is part of what the book is called.
    @Test
    func keepsAnAsideThatIsNotTheSeries() {
        #expect(SeriesNumbering.withoutSeries("Tin Garden (a collection)", in: "Ember") == "Tin Garden (a collection)")
    }

    /// A title that is nothing but its aside keeps it: there would be nothing left to call it.
    @Test
    func keepsATitleThatIsOnlyItsAside() {
        #expect(SeriesNumbering.withoutSeries("(Ember-4)", in: "Ember") == "(Ember-4)")
    }

    /// The series' name at the front of a title, and the figure it carried, belong to the series.
    @Test
    func takesTheSeriesNameOffTheFrontOfATitle() {
        #expect(SeriesNumbering.withoutSeries("Ember 3. Tin Garden", in: "Ember") == "Tin Garden")
    }

    /// A book whose title is its series' name is called that, so nothing is taken.
    @Test
    func keepsATitleThatIsOnlyTheSeriesName() {
        #expect(SeriesNumbering.withoutSeries("Ember", in: "Ember") == "Ember")
    }

    @Test
    func leavesATitleAloneWithoutASeries() {
        #expect(SeriesNumbering.withoutSeries("Tin Garden (Ember-4)", in: nil) == "Tin Garden (Ember-4)")
    }
}
