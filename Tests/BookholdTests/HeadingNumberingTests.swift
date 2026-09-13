//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookRenderer
import Testing

@testable import Bookhold

/// A heading carrying its own number is set as two things: the number small above, the name large
/// under it. Which means telling one from the other, and leaving alone every heading where that would
/// be a guess.
struct HeadingNumberingTests {
    @Test(arguments: [
        ("Глава 17 Край солёных озёр", "Глава 17", "Край солёных озёр"),
        ("Глава 17. Край солёных озёр", "Глава 17", "Край солёных озёр"),
        ("Глава 17: Край солёных озёр", "Глава 17", "Край солёных озёр"),
        ("Глава 17 — Край солёных озёр", "Глава 17", "Край солёных озёр"),
        ("Часть I. Дорога", "Часть I", "Дорога"),
        ("Глава третья. Возвращение", "Глава третья", "Возвращение"),
        ("Глава двадцать первая Дорога", "Глава двадцать первая", "Дорога"),
        ("Пролог. Начало", "Пролог", "Начало"),
        ("17. Край солёных озёр", "17", "Край солёных озёр"),
        // A figure numbers the chapter and stops: the words after it are the name, whatever they say.
        ("Глава 5 Три товарища", "Глава 5", "Три товарища"),
        ("Chapter 3. The Salt Lakes", "Chapter 3", "The Salt Lakes"),
        ("Chapter One: Beginnings", "Chapter One", "Beginnings"),
    ])
    func aNumberedHeadingIsPartedInTwo(heading: String, number: String, name: String) {
        let made = ChapterHeading.make(position: 4, title: heading)

        #expect(made.number == number)
        #expect(made.title == name)
    }

    /// Left whole, because parting it would be a guess or would leave nothing to part.
    @Test(arguments: [
        // Nothing to name.
        "Глава 17",
        "Пролог",
        "Chapter One",
        // A part word that is part of the name, not a part of the book.
        "Часть тела",
        // Russian numbers a chapter with an ordinal; a cardinal at the front is the name counting
        // something.
        "Глава Три товарища",
        // A figure at the front of a name is not a number unless something parts it from the name.
        "24 часа",
    ])
    func aHeadingThatWouldHaveToBeGuessedAtStandsAsItIs(heading: String) {
        let made = ChapterHeading.make(position: 4, title: heading)

        #expect(made.title == heading)
    }

    /// A heading with no number of its own is given the chapter's own count, as before.
    @Test
    func aHeadingWithNoNumberKeepsTheOneTheBookGivesIt() {
        let made = ChapterHeading.make(position: 4, title: "Край солёных озёр")

        #expect(made.number != nil)
        #expect(made.title == "Край солёных озёр")
    }
}
