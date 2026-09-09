//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Foundation
import Testing

@testable import ATReader

/// One book owned in both libraries is one book on the shelf.
///
/// Which copy is shown turns on where the reader has got to: a book being read stays with the service,
/// which is the only thing that knows their place; a book finished is better held as a file. Every
/// title here is invented.
@MainActor
struct LibraryPairingTests {
    private typealias Model = LibraryScreen.Model

    /// A positive id is a book from the service; a negative one came off a file.
    private static func book(
        id: Int,
        title: String = "Зимпель-ноль",
        author: String = "Имя Фамилия",
        order: Int? = nil,
        read: Double = 0,
        started: Bool = false
    ) -> Book {
        Book(
            id: id,
            title: title,
            authorLine: author,
            coverURL: nil,
            annotation: nil,
            seriesTitle: nil,
            seriesOrder: order,
            textLength: 1000,
            likeCount: nil,
            isFinished: true,
            status: nil,
            isPurchased: nil,
            adultOnly: nil,
            lastUpdateTime: .now,
            readingProgress: read,
            hasStartedReading: started,
            lastReadTime: nil,
            lastChapterId: nil,
            libraryState: .reading
        )
    }

    /// Two copies whose text hashes alike are one book, whatever either is called and whichever shelf
    /// each came off. Nothing else can say so: the two files carry different names and different
    /// volume numbers, which is exactly what stops the title comparison from pairing them.
    @Test
    func twoCopiesOfOneTextAreOneBook() {
        let held = [
            Self.book(id: -1, title: "Зимпель-ноль", order: 1, read: 0.2, started: true),
            Self.book(id: -2, title: "Зимпель-ноль (Зимпель-1)", order: 2, read: 0.9, started: true),
        ]
        let shelf = Model.oneOfEach(held, sameText: [ -1: "abc", -2: "abc" ])

        #expect(shelf.count == 1)
        // The copy the reader has got further into, since the words are the same either way.
        #expect(shelf.first?.id == -2)
    }

    /// Different text is different books, however alike the two hashes' owners look otherwise.
    @Test
    func copiesOfDifferentTextStayTwoBooks() {
        let held = [
            Self.book(id: -1, title: "Зимпель-ноль", order: 1),
            Self.book(id: -2, title: "Ворбат-один", order: 2),
        ]

        #expect(Model.oneOfEach(held, sameText: [ -1: "abc", -2: "def" ]).count == 2)
    }

    /// A book the service holds has no text on the device, so it pairs on its name as it always did.
    @Test
    func aTextlessCopyStillPairsByName() {
        let held = [ Self.book(id: 7, read: 0.5, started: true), Self.book(id: -1, read: 1) ]
        let shelf = Model.oneOfEach(held, sameText: [ -1: "abc" ])

        #expect(shelf.count == 1)
        #expect(shelf.first?.id == 7)
    }

    @Test
    func abookHeldOnceIsLeftAlone() {
        let only = [ Self.book(id: 1), Self.book(id: -1, title: "Другая книга") ]

        #expect(Model.oneOfEach(only).map(\.id) == [ 1, -1 ])
    }

    /// The one the reader is partway through: the service holds their place, the file does not.
    @Test
    func aBookBeingReadStaysWithTheService() {
        let paired = [
            Self.book(id: -1, read: 1),
            Self.book(id: 7, read: 0.4, started: true),
        ]

        #expect(Model.oneOfEach(paired).map(\.id) == [ 7 ])
    }

    /// Finished: the file wins, since nothing can withdraw it and no network is needed to open it.
    @Test
    func aFinishedBookIsHeldAsAFile() {
        let paired = [
            Self.book(id: 7, read: 1, started: true),
            Self.book(id: -1, read: 1),
        ]

        #expect(Model.oneOfEach(paired).map(\.id) == [ -1 ])
    }

    /// Not opened yet is not being read, so the file stands: a book brought across arrives read.
    @Test
    func anUnopenedBookIsHeldAsAFile() {
        let paired = [ Self.book(id: 7), Self.book(id: -1, read: 1) ]

        #expect(Model.oneOfEach(paired).map(\.id) == [ -1 ])
    }

    /// The same book written two ways is still the same book.
    @Test
    func aTitleIsMatchedPastItsPunctuation() {
        let paired = [
            Self.book(id: 7, title: "Зимпель-ноль", author: "Имя Фамилия", read: 0.5, started: true),
            Self.book(id: -1, title: "  зимпель ноль!  ", author: "имя фамилия", read: 1),
        ]

        #expect(Model.oneOfEach(paired).count == 1)
    }

    /// One library writes the series into the name and the other does not.
    @Test
    func aSeriesWrittenIntoTheNameIsStillTheSameBook() {
        let paired = [
            Self.book(id: 7, title: "Зимпель-ноль", read: 1, started: true),
            Self.book(id: -1, title: "Зимпель-ноль (Зимпель-1)", read: 1),
        ]

        #expect(Model.oneOfEach(paired).map(\.id) == [ -1 ])
    }

    /// But the same aside sometimes carries the volume, and two volumes are two books.
    @Test
    func twoVolumesAreNotOneBook() {
        let both = [
            Self.book(id: 7, title: "Зимпель (часть 2)", order: 2),
            Self.book(id: -1, title: "Зимпель (часть 3)", order: 3),
        ]

        #expect(Model.oneOfEach(both).count == 2)
    }

    /// A volume stated by only one of them is no evidence: they stay one book.
    @Test
    func aVolumeStatedOnceDoesNotSplitABook() {
        let paired = [
            Self.book(id: 7, title: "Зимпель-ноль", read: 1, started: true),
            Self.book(id: -1, title: "Зимпель-ноль (Зимпель-1)", order: 1, read: 1),
        ]

        #expect(Model.oneOfEach(paired).count == 1)
    }

    /// A title that is nothing but its aside keeps it, or there is nothing left to match on.
    @Test
    func aTitleThatIsOnlyAnAsideKeepsIt() {
        let both = [
            Self.book(id: 7, title: "(Зимпель-1)"),
            Self.book(id: -1, title: "(Ворбат-2)"),
        ]

        #expect(Model.oneOfEach(both).count == 2)
    }

    /// Two books that merely share an author are two books.
    @Test
    func differentBooksAreNotMerged() {
        let both = [
            Self.book(id: 7, title: "Зимпель-ноль"),
            Self.book(id: -1, title: "Ворбат-один"),
        ]

        #expect(Model.oneOfEach(both).count == 2)
    }

    /// And one that shares a title with another author is another book.
    @Test
    func aSharedTitleIsNotEnough() {
        let both = [
            Self.book(id: 7, author: "Первый Автор"),
            Self.book(id: -1, author: "Второй Автор"),
        ]

        #expect(Model.oneOfEach(both).count == 2)
    }

    /// The shelf keeps the order it was given, whichever copy of a pair wins.
    @Test
    func theShelfKeepsItsOrder() {
        let works = [
            Self.book(id: 1, title: "Первая"),
            Self.book(id: 7, title: "Зимпель-ноль", read: 0.4, started: true),
            Self.book(id: -1, title: "Зимпель-ноль", read: 1),
            Self.book(id: 2, title: "Третья"),
        ]

        #expect(Model.oneOfEach(works).map(\.title) == [ "Первая", "Зимпель-ноль", "Третья" ])
    }
}
