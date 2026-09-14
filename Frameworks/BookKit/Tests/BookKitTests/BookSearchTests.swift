//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import Testing

@testable import BookKit

/// Finding a passage by the words in it rather than by where it once stood.
///
/// What it has to survive is the book being read again: different spacing, different punctuation, a
/// different dash. The fixtures are written for the test.
struct BookSearchTests {
    private func text(_ source: String, find words: String) -> [String] {
        BookSearch.matches(of: words, in: source).map { range in
            let text = source as NSString

            return text.substring(with: NSRange(location: range.lowerBound, length: range.count))
        }
    }

    @Test
    func findsWordsWhateverTheCase() {
        #expect(text("Полина сказала", find: "полина") == [ "Полина" ])
        #expect(text("полина сказала", find: "ПОЛИНА") == [ "полина" ])
    }

    /// The point of the whole thing: a passage re-spaced or re-punctuated is the same passage.
    @Test
    func findsWordsThroughSpacesAndPunctuation() {
        #expect(!text("Раз, два — три.", find: "раздватри").isEmpty)
        #expect(!text("Раз два три", find: "раз, два — три").isEmpty)
        #expect(!text("Раз  два\nтри", find: "раз два три").isEmpty)
    }

    /// The stretch handed back is of the text as it stands, punctuation and all, so what is marked is
    /// what the reader can see.
    @Test
    func handsBackTheStretchOfTheTextItself() {
        #expect(text("Раз, два — три.", find: "разд") == [ "Раз, д" ])
    }

    @Test
    func findsEveryPlaceTheWordsAppear() {
        #expect(text("раз два раз", find: "раз").count == 2)
        #expect(text("ааа", find: "аа").count == 1, "matches may not overlap")
    }

    @Test
    func findsNothingWhereTheWordsAreGone() {
        #expect(text("Раз два", find: "четыре").isEmpty)
        #expect(text("Раз два", find: "").isEmpty)
        #expect(text("", find: "раз").isEmpty)
        #expect(text("раз", find: "раз два три").isEmpty)
    }

    /// A passage may read the same as another in the same chapter, so which one it was is kept with it.
    @Test
    func tellsOneOccurrenceFromAnother() {
        let source = "раз два раз три"
        let folded = BookSearch.fold(source)
        let second = BookSearch.match(of: "раз", occurrence: 1, in: folded)

        #expect(second?.lowerBound == 8)
        #expect(BookSearch.occurrence(of: "раз", at: 8, in: folded) == 1)
        #expect(BookSearch.occurrence(of: "раз", at: 0, in: folded) == 0)
    }

    /// A book edited since is better opened near the mark than not at all.
    @Test
    func fallsBackToTheFirstPlaceWhereTheCountNoLongerReaches() {
        let folded = BookSearch.fold("раз два")

        #expect(BookSearch.match(of: "раз", occurrence: 7, in: folded)?.lowerBound == 0)
        #expect(BookSearch.match(of: "четыре", occurrence: 0, in: folded) == nil)
    }

    /// Offsets are counted the way every other offset in the app is, so a mark found here lines up with
    /// a reading position and a page's own range.
    @Test
    func countsOffsetsTheWayTheRestOfTheAppDoes() {
        let source = "Ёлка раз"
        let found = BookSearch.matches(of: "раз", in: source)
        let text = source as NSString

        #expect(found.first?.lowerBound == text.range(of: "раз").location)
    }
}
