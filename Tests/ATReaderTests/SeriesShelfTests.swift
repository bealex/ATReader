//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Foundation
import Testing

@testable import ATReader

/// What a series card puts on its shelf, and which of the two ways it stands.
///
/// Every book is there in both modes. What changes is how much room a book the reader is done with
/// takes: a cover while every cover is shown, a spine while it isn't.
@MainActor
struct SeriesShelfTests {
    private typealias Model = LibraryScreen.Model

    @Test
    func acardOpensOnWhatIsLeftToRead() {
        let model = Self.model()

        #expect(!model.showsEveryCover("Зимпель"))
    }

    @Test
    func tappingTheTitleSwitchesBetweenTheTwoWays() {
        let model = Self.model()

        model.toggleCovers(of: "Зимпель")
        #expect(model.showsEveryCover("Зимпель"))

        model.toggleCovers(of: "Зимпель")
        #expect(!model.showsEveryCover("Зимпель"))
    }

    /// One card at a time: opening one series' covers leaves the others as they were.
    @Test
    func eachSeriesKeepsItsOwnWay() {
        let model = Self.model()

        model.toggleCovers(of: "Зимпель")
        #expect(!model.showsEveryCover("Ворбат"))
    }

    /// A book behind the reader stands as a spine, and one they haven't finished as a cover.
    @Test
    func abookAlreadyReadStandsAsASpine() {
        let works = [ Self.book(id: 1, read: 1), Self.book(id: 2, read: 0.3) ]
        let group = Model.Group(id: "series:Зимпель", series: "Зимпель", works: works, updated: .now)
        let slots = Self.model().slots(of: group)

        #expect(slots.map(Self.isRead) == [ true, false ])
    }

    /// A volume between two the reader holds that they don't keeps its place on the shelf.
    @Test
    func avolumeTheReaderDoesNotHoldKeepsItsPlace() {
        let works = [ Self.book(id: 1, title: "Зимпель (Зимпель-1)"), Self.book(id: 3, title: "Зимпель (Зимпель-3)") ]
        let group = Model.Group(
            id: "series:Зимпель",
            series: "Зимпель",
            works: works,
            updated: .now,
            numbering: SeriesNumbering.read(works)
        )
        let slots = Self.model().slots(of: group)

        #expect(slots.contains { if case .missing(2) = $0 { true } else { false } })
    }

    private static func isRead(_ slot: SeriesSlot) -> Bool {
        guard case let .book(_, _, _, isRead) = slot else { return false }

        return isRead
    }

    private static func model() -> Model { Model(session: SessionStore()) }

    private static func book(id: Int, title: String = "Зимпель", read: Double = 0) -> Book {
        Book(
            id: id,
            title: title,
            authorLine: "Имя Фамилия",
            coverURL: nil,
            annotation: nil,
            seriesTitle: "Зимпель",
            seriesOrder: nil,
            textLength: 1000,
            likeCount: nil,
            isFinished: true,
            status: nil,
            isPurchased: nil,
            adultOnly: nil,
            lastUpdateTime: .now,
            readingProgress: read,
            hasStartedReading: read > 0,
            lastReadTime: nil,
            lastChapterId: nil,
            libraryState: .reading
        )
    }
}
