//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Testing

@testable import Bookhold

/// Which spellings of a name the library files as one writer without being told. Every name here is
/// invented.
struct WriterNamesTests {
    @Test
    func filesTheSurnameFirstAndLastAsOneWriter() {
        let filed = WriterNames.filed([ "Сомов Пётр Ильич", "Пётр Ильич Сомов" ])

        #expect(filed["Сомов Пётр Ильич"] == filed["Пётр Ильич Сомов"])
    }

    @Test
    func filesANameWithoutItsPatronymicWithTheOneThatHasIt() {
        let filed = WriterNames.filed([ "Анна Верескова", "Анна Сергеевна Верескова" ])

        #expect(filed["Анна Верескова"] == filed["Анна Сергеевна Верескова"])
    }

    @Test
    func readsЁAsЕ() {
        let filed = WriterNames.filed([ "Пётр Сомов", "Петр Сомов" ])

        #expect(filed["Пётр Сомов"] == filed["Петр Сомов"])
    }

    @Test
    func filesAWriterUnderTheSpellingMostOfTheirBooksCarry() {
        let filed = WriterNames.filed([ "Сомов Пётр Ильич", "Пётр Сомов", "Пётр Сомов" ])

        #expect(filed["Сомов Пётр Ильич"] == "Пётр Сомов")
    }

    @Test
    func keepsTwoPatronymicsApart() {
        let filed = WriterNames.filed([ "Глеб Петрович Сорокопут", "Глеб Ильич Сорокопут", "Глеб Сорокопут" ])

        #expect(filed["Глеб Петрович Сорокопут"] != filed["Глеб Ильич Сорокопут"])
        // With two to choose from there is no telling whose the bare name is, so it joins neither.
        #expect(filed["Глеб Сорокопут"] == "Глеб Сорокопут")
    }

    /// A surname can end the way a patronymic does, and a two-word name has no patronymic to lose.
    @Test
    func keepsASurnameThatEndsLikeAPatronymic() {
        let filed = WriterNames.filed([ "Ника Орлович", "Ника Звонарёва", "Ника Петровна Орлович" ])

        #expect(filed["Ника Орлович"] != filed["Ника Звонарёва"])
        #expect(filed["Ника Орлович"] == filed["Ника Петровна Орлович"])
    }

    @Test
    func filesALatinNameInEitherOrderAsOneWriter() {
        let filed = WriterNames.filed([ "Tom Ashgrove", "Ashgrove Tom" ])

        #expect(filed["Tom Ashgrove"] == filed["Ashgrove Tom"])
    }

    @Test
    func leavesDifferentWritersApart() {
        let filed = WriterNames.filed([ "Анна Верескова", "Анна Облакова" ])

        #expect(filed["Анна Верескова"] != filed["Анна Облакова"])
    }
}
