//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookRenderer
import Testing
import UIKit

@testable import Bookhold

/// What searching the book rests on: a chapter is looked through as the book wrote its blocks, and the
/// reader is taken to the passage in a chapter that has since been laid out under a heading of its own.
///
/// The two counts differ, the heading standing in one and not the other, but they differ by the same
/// amount everywhere. That is what lets the reading nearest the offset be the passage that was found.
///
/// The text is generated nonsense: what is measured is where the words fall, not what they say.
@MainActor
struct FindInBookTests {
    @Test
    func theBlocksAndTheLaidOutChapterFindTheSamePlaces() async {
        let content = await ChapterContent.prepare(html: Self.html)
        let laid = await layout(of: content)

        let inBlocks = BookSearch.matches(of: Self.wanted, in: BookSearch.fold(Self.blocks(of: content)))
        let inChapter = BookSearch.matches(of: Self.wanted, in: BookSearch.fold(laid.sourceText))

        #expect(inBlocks.count > 1, "the chapter does not say it often enough to tell one from another")
        #expect(inBlocks.count == inChapter.count, "the two disagree about how often the book says it")

        let shifts = Set(zip(inBlocks, inChapter).map { $1.lowerBound - $0.lowerBound })

        #expect(shifts.count == 1, "the heading moves the places by \(shifts.sorted()) rather than by one amount")
    }

    /// A passage found in the blocks lands on the page it stands on, which is the whole point of it.
    @Test
    func aPassageFoundLandsOnThePageItStandsOn() async {
        let content = await ChapterContent.prepare(html: Self.html)
        let laid = await layout(of: content)

        let chapter = BookSearch.fold(laid.sourceText)
        let places = BookSearch.matches(of: Self.wanted, in: chapter)

        for (rank, found) in BookSearch.matches(of: Self.wanted, in: BookSearch.fold(Self.blocks(of: content)))
            .enumerated()
        {
            let nearest = places.min { abs($0.lowerBound - found.lowerBound) < abs($1.lowerBound - found.lowerBound) }

            #expect(
                nearest?.lowerBound == places[rank].lowerBound,
                "the passage at \(found.lowerBound) was taken for the one at \(nearest?.lowerBound ?? -1)"
            )
        }
    }

    /// Said often enough to tell one saying from another, and far enough apart that the nearest reading
    /// is never the one before it.
    private static let wanted = "восемь"

    private static let html = (1 ... 30)
        .map { "<p>Один да два на три — четыре, пять и шесть, а семь во восемь. Раз \($0) девять десять.</p>" }
        .joined()

    /// The chapter as the book wrote its blocks, which is what a search walks.
    private static func blocks(of content: ChapterContent) -> String {
        content.paragraphs.map(\.text).joined(separator: "\n")
    }

    private static var context: ChapterLayout.Context { JustificationTests.testContext }

    private func layout(of content: ChapterContent) async -> ChapterLayout {
        await ChapterLayout.make(
            chapterId: 1,
            content: content,
            heading: ChapterHeading(number: "Глава 1", title: "Восьмая сторона"),
            context: Self.context,
            startOffset: 0
        )
    }
}
