//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookRenderer
import Testing
import UIKit

@testable import Bookhold

/// A mark is written down with the words it stands on and found again by them, so the offsets a page is
/// cut at and the text those words are searched in have to be counted the same way.
///
/// The text is generated nonsense, written to bind: a Russian short word and a dash both pull a word
/// joiner into the text a page is set from.
@MainActor
struct BookmarkOffsetTests {
    @Test
    func theChapterRunsAsLongAsTheTextAMarkIsFoundIn() async {
        let laid = await layout(of: "<p>\(Self.filler)</p>")

        #expect((laid.sourceText as NSString).length == laid.sourceLength)
    }

    @Test
    func aMarkMadeOnAPageIsFoundOnThePageItWasMadeOn() async {
        let laid = await layout(of: "<p>\(Self.filler)</p>")

        #expect(laid.pageCount > 1, "the chapter came out too short to mark a page past the first")

        let whole = BookSearch.fold(laid.sourceText)

        for page in 0 ..< laid.pageCount {
            let start = laid.startOffset(of: laid.pages[page])
            let end = page + 1 < laid.pageCount ? laid.startOffset(of: laid.pages[page + 1]) : laid.sourceLength
            let words = laid.sourceText(in: start ..< min(end, start + Bookmark.wordsKept))

            let mark = Bookmark(
                workId: 7,
                chapterId: 1,
                startOffset: start,
                endOffset: end,
                text: words,
                occurrence: BookSearch.occurrence(of: words, at: start, in: whole),
                createdAt: .now
            )

            let place = mark.place(in: whole)

            #expect(
                place.lowerBound < max(end, start + 1) && start < max(place.upperBound, place.lowerBound + 1),
                "the mark on page \(page) was placed at \(place), off the \(start) ..< \(end) it was made on"
            )
        }
    }

    /// Long enough to run over several pages, and written so the binder has work to do.
    private static let filler = String(
        repeating: "Один да два на три — четыре, пять и шесть, а семь во восемь. ",
        count: 40
    )

    private static var context: ChapterLayout.Context { JustificationTests.testContext }

    private func layout(of html: String) async -> ChapterLayout {
        await ChapterLayout.make(
            chapterId: 1,
            content: await ChapterContent.prepare(html: html),
            heading: ChapterHeading(),
            context: Self.context,
            startOffset: 0
        )
    }
}
