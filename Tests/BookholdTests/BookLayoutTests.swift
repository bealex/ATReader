//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookRenderer
import SwiftUI
import Testing

@testable import Bookhold

/// A book cut into pages around the reader, a page at a time in either direction.
///
/// Nothing measures the book first, so what holds it together is that every page starts where the one
/// before it stopped. Walked either way, the pages have to cover every character of every chapter
/// once, keep the rules a compositor keeps, and fit the page they are set on.
@MainActor
struct BookLayoutTests {
    static let context = JustificationTests.testContext

    /// Three chapters, the middle one a section that may run on, each of many paragraphs.
    private static let shapes = [ (paragraphs: 30, level: 1), (paragraphs: 3, level: 2), (paragraphs: 45, level: 1) ]

    @Test
    func walkedForwardEveryCharacterStandsOnOnePage() async throws {
        let book = await Self.book()
        let title = try #require(await book.page(at: BookPosition(chapterId: 1, offset: BookPosition.titleOffset)))

        #expect(title.isTitle)

        let pages = await Self.walk(from: title) { await book.page(after: $0) }

        try Self.expectCovered(pages)
        Self.expectFitted(pages)
        Self.expectRulesKept(pages)
    }

    @Test
    func walkedBackwardEveryCharacterStandsOnOnePage() async throws {
        let book = await Self.book()
        let last = try #require(await book.page(at: BookPosition(chapterId: 3, offset: .max)))

        #expect(book.isLast(last))

        let pages = Array(await Self.walk(from: last) { await book.page(before: $0) }.reversed())

        #expect(pages.first?.isTitle == true, "walking back ends on the title page")

        try Self.expectCovered(pages)
        Self.expectFitted(pages)
        Self.expectRulesKept(pages)
    }

    /// A book opened part-way into a chapter starts its page on the line the reader stopped on.
    @Test
    func aPageOpensOnTheLineAPositionStandsOn() async throws {
        let book = await Self.book()
        let middle = try #require(await book.layout(of: 3)).sourceLength / 2
        let page = try #require(await book.page(at: BookPosition(chapterId: 3, offset: middle)))

        #expect(page.start.chapterId == 3)
        #expect(page.start.offset <= middle)
        #expect(middle < page.end.offset)

        let behind = try #require(await book.page(before: page))

        #expect(behind.end == page.start, "the page behind stops where this one starts")
    }

    /// Reached from behind, a chapter's opening that is too short for a page stands at the foot of it,
    /// so its lines run straight on to the page after.
    @Test
    func aChapterOpeningReachedFromBehindSinksToTheFoot() async throws {
        let book = await Self.book()
        // A few lines into the chapter, so what stands before it is the heading and those lines.
        let opened = try #require(await book.page(at: BookPosition(chapterId: 3, offset: 200)))
        let opening = try #require(await book.page(before: opened))
        let head = try #require(opening.pieces.first)
        let layout = head.layout

        #expect(opening.start == BookPosition(chapterId: 3, offset: 0))
        #expect(opening.end == opened.start)
        #expect(head.page.top > 0, "the short opening stands at the foot of its page")
        #expect(abs(layout.bottom(of: head.page) - Self.context.textSize.height) < 0.5)
    }

    /// A chapter the device cannot get stands as a page of its own, and the book goes on either side.
    @Test
    func aMissingChapterIsAPageTheBookGoesOnPast() async throws {
        let book = await Self.book(missing: [ 2 ])
        let last = try #require(await book.page(at: BookPosition(chapterId: 1, offset: .max)))
        let missing = try #require(await book.page(after: last))

        #expect(missing.content == .missing)
        #expect(missing.start.chapterId == 2)

        let next = try #require(await book.page(after: missing))

        #expect(next.start == BookPosition(chapterId: 3, offset: 0))
        #expect(await book.page(before: next)?.content == .missing)
    }

    /// The title page stands before the first chapter and nothing stands before it.
    @Test
    func theTitlePageOpensTheBook() async throws {
        let book = await Self.book()
        let first = try #require(await book.page(at: BookPosition(chapterId: 1, offset: 0)))
        let title = try #require(await book.page(before: first))

        #expect(title.isTitle)
        #expect(await book.page(before: title) == nil)
        #expect(await book.page(after: title)?.start == first.start)
    }

    /// A mark keeps the page it was made on, so the page asked for by that opening is the page the mark
    /// stood on rather than one beginning at the mark.
    @Test
    func aPlaceIsFoundOnThePageThatHoldsIt() async throws {
        let book = await Self.book()
        let length = try #require(await book.layout(of: 3)).sourceLength
        let wanted = [ 0, length / 3, length / 2, length - 1 ]
        let places = await book.pagePlaces(of: wanted, in: 3)

        #expect(places.count == wanted.count)

        for position in wanted {
            let place = try #require(places[position])
            let page = try #require(await book.page(at: BookPosition(chapterId: 3, offset: place.start)))
            let piece = try #require(page.pieces.first { $0.layout.chapterId == 3 })

            #expect(piece.layout.startOffset(of: piece.page) == place.start)
            #expect(position < piece.layout.endOffset(of: piece.page))

            let line = try #require(piece.layout.line(atPosition: position, on: piece.page))

            #expect(line.index - piece.page.lines.lowerBound == place.line)
        }
    }

    /// A mark whose words have moved carries its page with it, by however far they moved.
    @Test
    func aMarkCarriesItsPageWhereItsWordsHaveMoved() {
        let mark = Bookmark(
            workId: 1,
            chapterId: 1,
            startOffset: 500,
            endOffset: 560,
            pageStart: 420,
            lineOnPage: 4,
            createdAt: .now
        )

        #expect(mark.opening(at: 500 ..< 560) == 420)
        #expect(mark.opening(at: 530 ..< 590) == 450)
        #expect(mark.opening(at: 10 ..< 70) == 0, "a page cannot begin before the chapter does")
    }

    // MARK: - What every walk has to hold

    /// Each chapter's pieces run from its first character to its last with nothing left out or repeated.
    private static func expectCovered(_ pages: [BookPage]) throws {
        var spans: [Int: [(start: Int, end: Int, length: Int)]] = [:]

        for piece in pages.flatMap(\.pieces) {
            spans[piece.layout.chapterId, default: []].append((
                piece.layout.startOffset(of: piece.page),
                piece.layout.endOffset(of: piece.page),
                piece.layout.sourceLength
            ))
        }

        #expect(Set(spans.keys) == [ 1, 2, 3 ])

        for (chapter, run) in spans {
            let first = try #require(run.first)
            let last = try #require(run.last)

            #expect(first.start == 0, "chapter \(chapter) starts at \(first.start)")
            #expect(last.end == last.length, "chapter \(chapter) stops at \(last.end) of \(last.length)")

            for (before, after) in zip(run, run.dropFirst()) {
                #expect(after.start == before.end, "chapter \(chapter): a page stops at \(before.end), the next starts at \(after.start)")
            }
        }
    }

    /// No page runs past the foot of the text.
    private static func expectFitted(_ pages: [BookPage]) {
        for piece in pages.flatMap(\.pieces) {
            #expect(piece.layout.bottom(of: piece.page) <= context.textSize.height + 0.5)
        }
    }

    /// Where one page breaks in the middle of a chapter, no line of a paragraph is left alone at either
    /// side of the break.
    private static func expectRulesKept(_ pages: [BookPage]) {
        for (before, after) in zip(pages, pages.dropFirst()) {
            guard
                let foot = before.pieces.last,
                let head = after.pieces.first,
                foot.layout === head.layout,
                let last = foot.layout.typesetLines(on: foot.page).last,
                let first = head.layout.typesetLines(on: head.page).first
            else { continue }

            #expect(!(last.startsParagraph && !last.endsParagraph), "an orphan at the foot of \(before.id)")
            #expect(!(first.endsParagraph && !first.startsParagraph), "a widow at the head of \(after.id)")
        }
    }

    // MARK: - The book

    private static func walk(
        from start: BookPage,
        by step: (BookPage) async -> BookPage?
    ) async -> [BookPage] {
        var pages = [ start ]

        while pages.count < 400, let next = await step(pages[pages.count - 1]) { pages.append(next) }

        return pages
    }

    private static func book(missing: Set<Int> = []) async -> BookLayout {
        var contents: [Int: ChapterContent] = [:]

        for (index, shape) in shapes.enumerated() where !missing.contains(index + 1) {
            // Paragraphs of different lengths, so page breaks fall in different places in them.
            let html = (0 ..< shape.paragraphs)
                .map { "<p>\(JustificationTests.words(30 + ($0 * 53) % 90))</p>" }
                .joined()

            contents[index + 1] = await ChapterContent.prepare(html: html)
        }

        let texts = contents

        return BookLayout(
            chapters: shapes.enumerated().map { index, shape in
                BookLayout.Chapter(
                    id: index + 1,
                    heading: ChapterHeading.make(position: index + 1, title: nil),
                    opensItsOwnPage: shape.level <= 1
                )
            },
            context: context,
            content: { texts[$0] }
        )
    }
}
