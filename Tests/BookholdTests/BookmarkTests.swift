//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Testing

@testable import Bookhold

/// What a mark covers, which is what decides whether the page in front of the reader carries one.
struct BookmarkTests {
    private func mark(from start: Int, to end: Int, chapter: Int = 1) -> Bookmark {
        Bookmark(workId: 7, chapterId: chapter, startOffset: start, endOffset: end, createdAt: .now)
    }

    @Test
    func aPageCarriesTheMarkItStandsOn() {
        #expect(mark(from: 100, to: 200).overlaps(chapterId: 1, from: 100, to: 200))
        #expect(mark(from: 100, to: 200).overlaps(chapterId: 1, from: 150, to: 400))
        #expect(mark(from: 100, to: 200).overlaps(chapterId: 1, from: 0, to: 120))
        // A page inside a mark set over a longer stretch is still standing on it.
        #expect(mark(from: 0, to: 999).overlaps(chapterId: 1, from: 400, to: 500))
    }

    @Test
    func aPageCarriesNoneOfTheMarksBesideIt() {
        #expect(!mark(from: 100, to: 200).overlaps(chapterId: 1, from: 300, to: 400))
        #expect(!mark(from: 300, to: 400).overlaps(chapterId: 1, from: 100, to: 200))
        #expect(!mark(from: 100, to: 200).overlaps(chapterId: 2, from: 100, to: 200))
    }

    /// A mark stopping where the next page begins belongs to the page before it, or the page after
    /// would open showing itself already marked.
    @Test
    func touchingEndsAreNotAnOverlap() {
        #expect(!mark(from: 100, to: 200).overlaps(chapterId: 1, from: 200, to: 300))
        #expect(!mark(from: 200, to: 300).overlaps(chapterId: 1, from: 100, to: 200))
    }

    /// A chapter with nothing after it is one character deep as far as this is concerned, so a mark
    /// on its last page is still found.
    @Test
    func anEmptyStretchStillMeetsItself() {
        #expect(mark(from: 100, to: 100).overlaps(chapterId: 1, from: 100, to: 100))
    }

    @Test
    func howFarIntoTheChapterItStands() {
        #expect(mark(from: 250, to: 300).share(ofChapterLength: 1000) == 0.25)
        #expect(mark(from: 0, to: 10).share(ofChapterLength: 1000) == 0)
        #expect(mark(from: 2000, to: 2010).share(ofChapterLength: 1000) == 1)
        #expect(mark(from: 250, to: 300).share(ofChapterLength: nil) == nil)
        #expect(mark(from: 250, to: 300).share(ofChapterLength: 0) == nil)
    }
}
