//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Testing

@testable import Librix

/// Where a page falls in the whole book.
///
/// The worked example throughout: a title page, a chapter of three pages, and a chapter of two that
/// begins on the page the first one ended on. The book runs to five pages, of which page four belongs
/// to both chapters.
struct BookPagingTests {
    private let paging = BookPaging(firstPages: [ 1: 2, 2: 4 ], chapterPages: [ 1: 3, 2: 2 ], length: 5)

    @Test
    func standsAChaptersFirstPageWhereTheChapterBegins() {
        #expect(paging.page(of: 1, within: 1) == 2)
        #expect(paging.page(of: 2, within: 1) == 4)
    }

    @Test
    func countsOnFromThere() {
        #expect(paging.page(of: 1, within: 2) == 3)
        #expect(paging.page(of: 1, within: 3) == 4)
        #expect(paging.page(of: 2, within: 2) == 5)
    }

    @Test
    func endsTheLastChapterOnTheLastPageOfTheBook() {
        #expect(paging.page(of: 2, within: 2) == paging.length)
    }

    @Test
    func givesBothChaptersTheSamePageWhereOneRunsOnFromTheOther() {
        #expect(paging.page(of: 1, within: 3) == paging.page(of: 2, within: 1))
    }

    @Test
    func knowsNothingOfAChapterNobodyHasMeasured() {
        #expect(paging.page(of: 3, within: 1) == nil)
    }

    @Test
    func lengthensTheBookByWhateverAChapterHasGainedSinceItWasMeasured() {
        #expect(paging.length(with: 2, measuring: 6) == 9)
    }

    @Test
    func shortensItByWhateverAChapterHasLost() {
        #expect(paging.length(with: 2, measuring: 1) == 4)
    }

    @Test
    func leavesTheLengthAloneForAChapterItNeverMeasured() {
        #expect(paging.length(with: 3, measuring: 40) == paging.length)
    }

    @Test
    func neverWalksTheReaderPastTheEnd() {
        // What the reader saw: page 469 of 465, because the chapter they were in had grown since the
        // pass measured it and the book's length had not caught up.
        let grown = paging.length(with: 2, measuring: 6)

        #expect(paging.page(of: 2, within: 6) ?? 0 <= grown)
    }

    /// What the reader saw: a book of more than a thousand pages opened as "page 2 of 46", the length of
    /// the two chapters measured before it opened.
    @Test
    func guessesTheRestOfTheBookAtTheRateTheMeasuredTextRan() {
        #expect(BookPaging.estimate(90_000, at: 46, per: 10_000) == 414)
    }

    @Test
    func roundsAGuessUpToAWholePage() {
        #expect(BookPaging.estimate(1, at: 46, per: 10_000) == 1)
    }

    @Test
    func guessesNothingUntilSomethingHasBeenMeasured() {
        #expect(BookPaging.estimate(90_000, at: 0, per: 0) == 0)
    }

    @Test
    func guessesNothingOnceEverythingHasBeenMeasured() {
        #expect(BookPaging.estimate(0, at: 46, per: 10_000) == 0)
    }
}
