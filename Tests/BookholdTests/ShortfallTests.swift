//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookRenderer
import Foundation
import Testing

@testable import Bookhold

/// A page cut against the measure in force fills it; one cut against another measure stops short, and
/// that shortfall is what tells the reader to cut it again.
@MainActor
struct ShortfallTests {
    private static let tall = JustificationTests.testContext

    private static var short: ChapterLayout.Context {
        var context = tall
        context.pageSize.height -= 120
        return context
    }

    @Test
    func aPageCutAgainstTheMeasureInForceFillsIt() async throws {
        let book = await Self.book(Self.tall)
        let page = try #require(await book.page(at: BookPosition(chapterId: 1, offset: 2000)))

        #expect(book.shortfall(of: page) < 1)
    }

    /// The fault the reader cuts again for: a page cut for a shallower measure, shown in a deeper one.
    @Test
    func aPageCutForAShallowerMeasureStandsShortInTheDeeperOne() async throws {
        let shallow = await Self.book(Self.short)
        let deep = await Self.book(Self.tall)
        let page = try #require(await shallow.page(at: BookPosition(chapterId: 1, offset: 2000)))

        #expect(shallow.shortfall(of: page) < 1)
        #expect(deep.shortfall(of: page) >= 1)
    }

    /// A chapter's last page stops where its text stops, which is short of nothing.
    @Test
    func aChaptersLastPageIsShortOfNothing() async throws {
        let book = await Self.book(Self.tall)
        let last = try #require(await book.page(at: BookPosition(chapterId: 1, offset: .max)))

        #expect(book.shortfall(of: last) == 0)
    }

    private static func book(_ context: ChapterLayout.Context) async -> BookLayout {
        let html = (0 ..< 40).map { "<p>\(JustificationTests.words(30 + ($0 * 53) % 90))</p>" }.joined()
        let content = await ChapterContent.prepare(html: html)

        return BookLayout(
            chapters: [ BookLayout.Chapter(id: 1, heading: ChapterHeading.make(position: 1, title: nil), opensItsOwnPage: true) ],
            context: context,
            content: { _ in content }
        )
    }
}
