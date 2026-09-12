//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Foundation
import Testing

@testable import Librix

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
        series: String? = nil,
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
            seriesTitle: series,
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
        #expect(shelf.first?.id == -1)
    }

    /// Two copies of one book inside a series the reader assembled are one book. What is filed for
    /// such a series is each book's place in the list they arranged, and the two copies were given two
    /// places; read as volumes, those places say the copies are different books.
    @Test
    func twoCopiesInsideAnArrangedSeriesAreOneBook() {
        let held = [
            Self.book(id: 7, title: "Зимпель-ноль (Зимпель-1)", series: "Зимпель", order: 1, read: 0.5, started: true),
            Self.book(id: -1, title: "Зимпель-ноль", series: "Зимпель", order: 2, read: 1),
        ]

        #expect(Model.oneOfEach(held, arranged: [ "Зимпель" ]).count == 1)
    }

    /// In a series nobody arranged, a stated volume is still what tells two books apart.
    @Test
    func statedVolumesStillTellTwoBooksApart() {
        let held = [
            Self.book(id: 7, title: "Зимпель (часть 2)", series: "Зимпель", order: 2),
            Self.book(id: -1, title: "Зимпель (часть 3)", series: "Зимпель", order: 3),
        ]

        #expect(Model.oneOfEach(held).count == 2)
    }

    /// The two libraries spell one name differently, which is the ordinary case rather than the odd
    /// one: keeping the author in the key means the copies never meet to be compared at all.
    @Test
    func copiesSpellingTheAuthorDifferentlyAreOneBook() {
        let held = [
            Self.book(id: 7, title: "Кризис", author: "Фамилия Имя Отчество", read: 0.5, started: true),
            Self.book(id: -1, title: "Кризис", author: "Имя Фамилия", read: 1),
        ]

        #expect(Model.oneOfEach(held).count == 1)
    }

    /// A co-author on some volumes and not others still names the same writer.
    @Test
    func acoAuthorOnOneCopyIsStillTheSameBook() {
        let held = [
            Self.book(id: 7, title: "Кризис", author: "Имя Фамилия, Второе Имя"),
            Self.book(id: -1, title: "Кризис", author: "Имя Фамилия"),
        ]

        #expect(Model.oneOfEach(held).count == 1)
    }

    /// One name in common is not evidence where both carry two: a shared given name is not an author.
    @Test
    func oneSharedNameIsNotTheSameAuthor() {
        let held = [
            Self.book(id: 7, title: "Кризис", author: "Имя Первая"),
            Self.book(id: -1, title: "Кризис", author: "Имя Вторая"),
        ]

        #expect(Model.oneOfEach(held).count == 2)
    }

    /// One library writes the series into the title and the other leaves it out, so a stated volume
    /// on each side is not what tells them apart.
    @Test
    func acopyCarryingTheSeriesAsideIsStillTheSameBook() {
        let held = [
            Self.book(id: 7, title: "Зимпель-ноль (Зимпель-1)", series: "Зимпель", order: 1),
            Self.book(id: -1, title: "Зимпель-ноль", series: "Зимпель", order: 4),
        ]

        #expect(Model.oneOfEach(held).count == 1)
    }

    /// Two volumes sharing a base title are told apart by the asides, which is what they are for.
    @Test
    func twoVolumesSharingABaseTitleStayTwoBooks() {
        let held = [
            Self.book(id: 7, title: "Зимпель-ноль (Зимпель-1)", series: "Зимпель", order: 1),
            Self.book(id: -1, title: "Зимпель-ноль (Зимпель-2)", series: "Зимпель", order: 2),
        ]

        #expect(Model.oneOfEach(held).count == 2)
    }

    /// The kept copy wears the fuller of the two titles. Which copy is kept turns on where the reader
    /// is, so it can be the one whose title leaves the series and its volume out, and a numbering is
    /// whatever every title in the series has in common.
    @Test
    func theKeptCopyWearsTheFullerTitle() {
        let held = [
            Self.book(id: 7, title: "Зимпель-ноль (Зимпель-1)", series: "Зимпель", read: 0.5, started: true),
            Self.book(id: -1, title: "Зимпель-ноль", series: "Зимпель", read: 1),
        ]
        let shelf = Model.oneOfEach(held)

        #expect(shelf.count == 1)
        // The file is kept, and takes the service copy's fuller title.
        #expect(shelf.first?.id == -1)
        #expect(shelf.first?.title == "Зимпель-ноль (Зимпель-1)")
    }

    /// One library writes a volume as a word and a figure where the other writes it as a figure alone.
    @Test
    func avolumeSaidTwoWaysIsOneBook() {
        let held = [
            Self.book(id: 7, title: "Зимпель. Том 2", series: "Зимпель"),
            Self.book(id: -1, title: "Зимпель-2", series: "Зимпель"),
        ]

        #expect(Model.oneOfEach(held).count == 1)
    }

    /// The word only goes where a figure follows it. A book with somebody called Tom in its title is
    /// not stating a volume, and two of those are still two books.
    @Test
    func awordThatOnlyLooksLikeAVolumeIsKept() {
        let held = [
            Self.book(id: 7, title: "Том Зимпель", series: "Зимпель"),
            Self.book(id: -1, title: "Зимпель", series: "Зимпель"),
        ]

        #expect(Model.oneOfEach(held).count == 2)
    }

    @Test
    func abookHeldOnceIsLeftAlone() {
        let only = [ Self.book(id: 1), Self.book(id: -1, title: "Другая книга") ]

        #expect(Model.oneOfEach(only).map(\.id) == [ 1, -1 ])
    }

    /// The copy on the device stands even for a book the reader is partway through on the service:
    /// its words are here, which is what a shelf is for.
    @Test
    func abookBeingReadIsStillHeldAsAFile() {
        let paired = [
            Self.book(id: -1, read: 1),
            Self.book(id: 7, read: 0.4, started: true),
        ]

        #expect(Model.oneOfEach(paired).map(\.id) == [ -1 ])
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
