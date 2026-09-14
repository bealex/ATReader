//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import Testing

@testable import BookKit

/// Where a mark stands once the book has been read again and every offset in it has moved.
///
/// The fixtures are written for the test. What matters is that the marked words keep their place in
/// them while everything around them shifts.
struct BookmarkPlaceTests {
    private func mark(_ words: String?, at start: Int, length: Int = 6, occurrence: Int = 0) -> Bookmark {
        Bookmark(
            workId: -1,
            chapterId: -2,
            startOffset: start,
            endOffset: start + length,
            text: words,
            occurrence: occurrence,
            createdAt: .now
        )
    }

    /// The whole point: words shifted along by an edit are still found where they now stand.
    @Test
    func findsTheWordsAfterEverythingAroundThemHasMoved() {
        let was = "Раз два три четыре"
        let now = "Вставка. Раз два три четыре"
        let start = (was as NSString).range(of: "три").location
        let written = mark("три", at: start)

        #expect(written.place(in: BookSearch.fold(was)).lowerBound == start)
        #expect(written.place(in: BookSearch.fold(now)).lowerBound == (now as NSString).range(of: "три").location)
    }

    /// The words say where it begins; how far it ran is its own, a page being what the reader could see.
    @Test
    func keepsTheStretchItCovered() {
        let place = mark("три", at: 8, length: 40).place(in: BookSearch.fold("Раз два три четыре"))

        #expect(place.count == 40)
    }

    /// A mark written before words were kept is found by its offsets, exactly as it always was.
    @Test
    func fallsBackToTheOffsetsOfAMarkWithNoWords() {
        let place = mark(nil, at: 4, length: 9).place(in: BookSearch.fold("Раз два три"))

        #expect(place == 4 ..< 13)
    }

    /// A passage may read the same as another in the chapter, so which one it was is kept with it.
    @Test
    func tellsOneOccurrenceOfTheSameWordsFromAnother() {
        let text = BookSearch.fold("раз два раз три")

        #expect(mark("раз", at: 0, occurrence: 0).place(in: text).lowerBound == 0)
        #expect(mark("раз", at: 8, occurrence: 1).place(in: text).lowerBound == 8)
    }

    /// Words gone from the chapter leave the mark where it was written, rather than losing it.
    @Test
    func leavesAMarkWhereItWasWhenItsWordsAreGone() {
        let place = mark("пятое", at: 4, length: 5).place(in: BookSearch.fold("Раз два три"))

        #expect(place == 4 ..< 9)
    }

    /// Re-spacing and re-punctuating are what a reading of the book changes most, and neither moves it.
    @Test
    func findsWordsRepunctuatedSinceTheyWereMarked() {
        let now = "Раз, два — три!"
        let place = mark("два три", at: 0).place(in: BookSearch.fold(now))

        #expect(place.lowerBound == (now as NSString).range(of: "два").location)
    }
}
