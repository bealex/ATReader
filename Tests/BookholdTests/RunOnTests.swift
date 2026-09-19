//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import BookKit
import BookRenderer
import BookStorage
import SwiftUI
import Testing
import UIKit

@testable import Bookhold

/// A chapter may finish the page the one before it ended on, but only if it brings a few lines of
/// itself along. A heading with nothing under it, or a line or two, is a title stranded at the foot of
/// the page, and the chapter belongs on a page of its own.
///
/// The free space cannot answer this on its own: it is measured in body lines, and a heading stands far
/// taller than those, so a gap that looks like six lines can hold a heading and nothing else. These
/// check the count the rule actually reads, and then the pages the book makes of it either way round.
@MainActor
struct RunOnTests {
    static let context = JustificationTests.testContext

    private func layout(words: Int = 120, startOffset: CGFloat) async -> ChapterLayout {
        await ChapterLayout.make(
            chapterId: 1,
            content: await ChapterContent.prepare(html: "<p>\(JustificationTests.words(words))</p>"),
            heading: ChapterHeading.make(position: 3, title: "Часть третья"),
            context: Self.context,
            startOffset: startOffset
        )
    }

    /// A chapter starting a page of its own always brings its text with it.
    @Test
    func aChapterOnItsOwnPageCarriesItsText() async {
        let layout = await layout(startOffset: 0)

        #expect(layout.bodyLineCount(on: layout.pages[0]) >= BookLayout.runOnLineMinimum)
    }

    /// A gap deep enough to look inviting, which the heading fills on its own. The count has to come
    /// back below the minimum so the chapter is moved off the shared page.
    @Test(arguments: [ 30.0, 60.0, 90.0 ])
    func aGapThatOnlyFitsAHeadingBringsTooFewLines(free: CGFloat) async {
        let layout = await layout(startOffset: Self.context.textSize.height - free)
        let lines = layout.bodyLineCount(on: layout.pages[0])

        #expect(lines < BookLayout.runOnLineMinimum, "\(Int(free))pt held \(lines) lines, so the chapter would run on")
    }

    /// Given real room, a chapter is allowed to share the page.
    ///
    /// Real room is more than it was: a chapter's heading is the first-level title of its block and
    /// stands in twelve lines of air, so most of a page has to be free before any of its text lands.
    @Test
    func aDeepGapLetsTheChapterRunOn() async {
        let layout = await layout(startOffset: Self.context.textSize.height * 0.15)

        #expect(layout.bodyLineCount(on: layout.pages[0]) >= BookLayout.runOnLineMinimum)
    }

    // MARK: - Two chapters on one page

    /// A section inside a chapter carries on under the end of the one before it.
    @Test
    func aSectionRunsOnUnderAShortChapter() async throws {
        let book = await Self.book([ (words: 12, level: 1), (words: 400, level: 2) ])
        let first = try #require(await book.page(at: BookPosition(chapterId: 1, offset: 0)))

        #expect(first.pieces.map(\.layout.chapterId) == [ 1, 2 ])
    }

    /// A part title is a chapter of a heading and nothing else. The chapter after it follows it down the
    /// page rather than leaving the page empty under it.
    @Test
    func aPartTitleLetsItsFirstChapterFollowIt() async throws {
        let book = await Self.book([ (words: 0, level: 1), (words: 400, level: 2) ])
        let first = try #require(await book.page(at: BookPosition(chapterId: 1, offset: 0)))

        #expect(first.pieces.map(\.layout.chapterId) == [ 1, 2 ])
    }

    /// A division the book names among its own top ones opens a page, however much room is left above.
    @Test
    func aTopDivisionOpensItsOwnPage() async throws {
        let book = await Self.book([ (words: 12, level: 1), (words: 400, level: 1) ])
        let first = try #require(await book.page(at: BookPosition(chapterId: 1, offset: 0)))

        #expect(first.pieces.map(\.layout.chapterId) == [ 1 ])
    }

    /// Reached from behind, the page the two share is the same page: the end of the one above, and the
    /// opening of the other at the foot, running straight on to the page after it.
    @Test
    func turningBackOntoASharedPageStacksTheTwoAgain() async throws {
        let book = await Self.book([ (words: 12, level: 1), (words: 400, level: 2) ])
        let shared = try #require(await book.page(at: BookPosition(chapterId: 1, offset: 0)))
        let after = try #require(await book.page(after: shared))
        let back = try #require(await book.page(before: after))
        let pieces = back.pieces

        #expect(pieces.map(\.layout.chapterId) == [ 1, 2 ])
        #expect(back.end == after.start, "the opening reaches the page after it")

        let head = try #require(pieces.last)

        #expect(
            abs(head.layout.bottom(of: head.page) - Self.context.textSize.height) < 0.5,
            "the opening stands at the foot of the page"
        )
    }

    /// A book of chapters of generated words, each as long and as deep in the book as asked.
    static func book(_ shapes: [(words: Int, level: Int)]) async -> BookLayout {
        var contents: [Int: ChapterContent] = [:]

        for (index, shape) in shapes.enumerated() {
            let html = shape.words > 0 ? "<p>\(JustificationTests.words(shape.words))</p>" : ""

            contents[index + 1] = await ChapterContent.prepare(html: html)
        }

        let texts = contents

        return BookLayout(
            chapters: shapes.enumerated().map { index, shape in
                BookLayout.Chapter(
                    id: index + 1,
                    heading: ChapterHeading.make(position: index + 1, title: "Часть \(index + 1)"),
                    opensItsOwnPage: shape.level <= 1
                )
            },
            context: context,
            content: { texts[$0] }
        )
    }
}
