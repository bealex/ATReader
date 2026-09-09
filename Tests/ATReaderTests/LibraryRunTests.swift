//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Foundation
import Testing

@testable import ATReader

/// What the shelf folds away inside a series, and what it leaves standing.
///
/// A long run of books already read is one line; anything the reader still has to reach stays a row of
/// its own. The books are generated, since only what has been read and how the titles number
/// themselves matters here.
@MainActor
struct LibraryRunTests {
    @Test
    func aLongRunOfReadBooksFoldsIntoOneLine() {
        let rows = Self.shelf(read: [ true, true, true, true, false ])

        #expect(rows.count == 2)
        #expect(Self.folded(rows.first)?.rows.count == 4)
    }

    /// Three lines are already short enough to read past, so nothing is gained by hiding them.
    @Test
    func threeReadBooksStayThreeLines() {
        let rows = Self.shelf(read: [ true, true, true, false ])

        #expect(rows.count == 4)
        #expect(rows.allSatisfy { Self.folded($0) == nil })
    }

    /// The run has to be sequential: a book still being read splits one long run into two short ones.
    @Test
    func aBookStillBeingReadBreaksTheRun() {
        let rows = Self.shelf(read: [ true, true, false, true, true ])

        #expect(rows.count == 5)
        #expect(rows.allSatisfy { Self.folded($0) == nil })
    }

    /// A series read right through is one line and nothing else.
    @Test
    func aSeriesReadRightThroughIsOneLine() {
        let rows = Self.shelf(read: [ true, true, true, true, true ])

        #expect(rows.count == 1)
        #expect(Self.folded(rows.first)?.rows.count == 5)
    }

    @Test
    func aFoldedRunCarriesTheVolumesItCovers() {
        let rows = Self.shelf(read: [ true, true, true, true, false ])

        #expect(Self.folded(rows.first)?.numbers == 1 ... 4)
    }

    /// The folded line is the volumes and nothing else, so a run with none to show is no run at all.
    @Test
    func aRunWithNothingToNumberIsNotARun() {
        let unnumbered = (1 ... 4).map {
            LibraryScreen.Model.SeriesRow.book(Self.book(number: $0, isRead: true), number: nil, title: "Книга")
        }

        #expect(LibraryScreen.Model.FoldedRun(unnumbered, kind: .read) == nil)
        #expect(LibraryScreen.Model.FoldedRun([], kind: .missing) == nil)
        #expect(LibraryScreen.Model.FoldedRun([], kind: .read) == nil)
    }

    @Test
    func openingARunShowsItsBooksAgain() {
        let model = Self.model()
        let group = Self.group(read: [ true, true, true, true, false ])

        guard
            let folded = Self.folded(model.shelfRows(of: group).first)
        else {
            Issue.record("the run was not folded")
            return
        }

        model.open(folded)
        #expect(model.shelfRows(of: group).count == 5)

        model.closeRuns()
        #expect(model.shelfRows(of: group).count == 2)
    }

    /// Picking books out leaves every row showing: a folded run hides books the reader is reaching for.
    @Test
    func pickingBooksOutUnfoldsEveryRun() {
        let model = Self.model()
        let group = Self.group(read: [ true, true, true, true, false ])

        model.isSelecting = true
        #expect(model.shelfRows(of: group).count == 5)
    }

    /// Volumes the reader doesn't hold fold the same way the ones they have read do: four lines
    /// saying "not here" push the book they are actually reading off the screen.
    @Test
    func aLongRunOfMissingVolumesFoldsIntoOneLine() {
        let rows = Self.model().shelfRows(of: Self.group(held: [ 1, 6 ]))

        #expect(rows.count == 3)
        #expect(rows.compactMap { Self.folded($0)?.numbers } == [ 2 ... 5 ])
    }

    /// Three gaps are already short enough to read past, like three read books.
    @Test
    func threeMissingVolumesStayThreeLines() {
        let rows = Self.model().shelfRows(of: Self.group(held: [ 1, 5 ]))

        #expect(rows.count == 5)
        #expect(rows.allSatisfy { Self.folded($0) == nil })
    }

    /// A run is one thing throughout: read books and gaps that meet fold into two lines, not one
    /// claiming to be both.
    @Test
    func readBooksAndGapsFoldSeparately() {
        let rows = Self.model().shelfRows(of: Self.group(held: [ 1, 2, 3, 4, 10 ], read: [ 1, 2, 3, 4 ]))

        #expect(rows.compactMap { Self.folded($0)?.kind } == [ .read, .missing ])
        #expect(rows.count == 3)
    }

    // MARK: - A shelf to file

    private static func model() -> LibraryScreen.Model {
        LibraryScreen.Model(session: SessionStore())
    }

    /// One series, numbered in its own titles, with the given books read through.
    private static func group(read: [Bool]) -> LibraryScreen.Model.Group {
        // Volume one first, so a folded run reads from the earliest book the reader is done with.
        let works = read.enumerated().map { index, isRead in
            book(number: index + 1, isRead: isRead)
        }

        return .init(
            id: "series:Эмбер",
            series: "Эмбер",
            works: works,
            updated: .now,
            numbering: SeriesNumbering.read(works)
        )
    }

    /// One series holding only the volumes named, so the rest of the run is a gap.
    private static func group(held: [Int], read: Set<Int> = []) -> LibraryScreen.Model.Group {
        let works = held.map { book(number: $0, isRead: read.contains($0)) }

        return .init(
            id: "series:Эмбер",
            series: "Эмбер",
            works: works,
            updated: .now,
            numbering: SeriesNumbering.read(works)
        )
    }

    private static func shelf(read: [Bool]) -> [LibraryScreen.Model.ShelfRow] {
        model().shelfRows(of: group(read: read))
    }

    private static func folded(_ row: LibraryScreen.Model.ShelfRow?) -> LibraryScreen.Model.FoldedRun? {
        guard case let .folded(folded) = row else { return nil }

        return folded
    }

    private static func book(number: Int, isRead: Bool) -> Book {
        Book(
            id: number,
            title: "Эмбер \(number). Книга",
            authorLine: "Автор",
            coverURL: nil,
            annotation: nil,
            seriesTitle: "Эмбер",
            seriesOrder: number,
            textLength: 1000,
            likeCount: nil,
            isFinished: true,
            status: nil,
            isPurchased: nil,
            adultOnly: nil,
            lastUpdateTime: .now,
            readingProgress: isRead ? 1 : 0.4,
            hasStartedReading: true,
            lastReadTime: nil,
            lastChapterId: nil,
            libraryState: .reading
        )
    }
}
