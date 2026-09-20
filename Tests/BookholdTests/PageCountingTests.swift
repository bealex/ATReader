//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Testing

@testable import Bookhold

/// The book's length in pages is an estimate that every turn forward corrects: the page just left keeps
/// its number and the page arrived on takes the next one.
@MainActor
struct PageCountingTests {
    /// How a page is numbered, which is what the count has to satisfy.
    private func number(of share: Double, in total: Int) -> Int {
        max(1, Int((Double(total) * share).rounded()))
    }

    @Test
    func aCountThatRepeatsANumberGrows() {
        let total = 100
        let was = 0.500
        let now = 0.502

        #expect(number(of: was, in: total) == number(of: now, in: total), "the numbers already differ")

        let counted = ReaderScreen.Model.pages(holding: 50, at: was, reaching: 51, at: now, from: total)

        #expect(counted > total)
        #expect(number(of: now, in: counted) == 51)
    }

    /// Where the two places are far enough apart for a length to number both, it numbers both.
    @Test
    func aCountHoldsThePageTheReaderLeft() {
        let counted = ReaderScreen.Model.pages(holding: 20, at: 0.5, reaching: 21, at: 0.53, from: 40)

        #expect(number(of: 0.5, in: counted) == 20)
        #expect(number(of: 0.53, in: counted) == 21)
    }

    @Test
    func aCountThatSkipsANumberShrinks() {
        let total = 1000
        let was = 0.500
        let now = 0.504

        #expect(number(of: now, in: total) - number(of: was, in: total) > 1, "the numbers already step by one")

        let counted = ReaderScreen.Model.pages(holding: 500, at: was, reaching: 501, at: now, from: total)

        #expect(counted < total)
        #expect(number(of: now, in: counted) == 501)
    }

    @Test
    func aCountThatAlreadyStepsByOneStaysWhereItIs() {
        let total = 200
        let was = 0.5
        let now = 0.505

        #expect(number(of: was, in: total) == 100)
        #expect(number(of: now, in: total) == 101)

        #expect(ReaderScreen.Model.pages(holding: 100, at: was, reaching: 101, at: now, from: total) == total)
    }

    /// A spread turns two pages at once, so the number has to move by two.
    @Test
    func aSpreadCountsBothItsPages() {
        let counted = ReaderScreen.Model.pages(holding: 50, at: 0.5, reaching: 52, at: 0.52, from: 100)

        #expect(number(of: 0.52, in: counted) == 52)
    }

    /// The first page of the book holds no number of its own, every count putting it at one.
    @Test
    func theOpeningOfTheBookCountsFromTheNewPage() {
        let counted = ReaderScreen.Model.pages(holding: 1, at: 0, reaching: 2, at: 0.004, from: 150)

        #expect(number(of: 0.004, in: counted) == 2)
    }

    /// A count is never shorter than the page the reader is standing on.
    @Test
    func aCountReachesThePageItIsCounting() {
        let counted = ReaderScreen.Model.pages(holding: 300, at: 0.999, reaching: 301, at: 1, from: 300)

        #expect(counted >= 301)
    }
}
