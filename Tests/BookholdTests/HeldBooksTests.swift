//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Foundation
import Testing

@testable import Bookhold

/// Which of a catalogue's books the reader already has, matched on the little a catalogue gives.
@MainActor
struct HeldBooksTests {
    @Test
    func aTitleSpelledDifferentlyIsStillTheSameBook() {
        let held = HeldBooks()

        held.note([ book(title: "Тримунда, или Тень", author: "Вирен Долосский") ])

        #expect(held.holds(title: "тримунда или тень", authors: [ "Долосский, Вирен" ]))
    }

    @Test
    func anotherWritersBookOfTheSameNameIsNotIt() {
        let held = HeldBooks()

        held.note([ book(title: "Пятый пролёт", author: "Вирен Долосский") ])

        #expect(!held.holds(title: "Пятый пролёт", authors: [ "Онега Плавь" ]))
    }

    /// A catalogue that names no author is taken at its title, which is all it offered.
    @Test
    func aBookWithNoAuthorGoesOnItsTitle() {
        let held = HeldBooks()

        held.note([ book(title: "Пятый пролёт", author: "Вирен Долосский") ])

        #expect(held.holds(title: "Пятый пролёт", authors: []))
    }

    /// An initial agrees with every name there is, so the surname is what decides.
    @Test
    func anInitialDecidesNothing() {
        let held = HeldBooks()

        held.note([ book(title: "Пятый пролёт", author: "В. Долосский") ])

        #expect(held.holds(title: "Пятый пролёт", authors: [ "Вирен Долосский" ]))
    }

    @Test
    func aBookThatIsNotThereIsNotHeld() {
        let held = HeldBooks()

        held.note([ book(title: "Пятый пролёт", author: "Вирен Долосский") ])

        #expect(!held.holds(title: "Тримунда", authors: [ "Вирен Долосский" ]))
    }

    private func book(title: String, author: String) -> Book {
        Book(id: 1, title: title, authorLine: author, coverURL: nil, annotation: nil)
    }
}
