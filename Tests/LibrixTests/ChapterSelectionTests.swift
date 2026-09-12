//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookRenderer
import Foundation
import Testing

@testable import Librix

/// Picking text off a drawn page.
///
/// A drawn page has no selection of its own, so what is checked here is the arithmetic that stands in
/// for one: which character a point is over, where the word around it ends, and what a drag between
/// two points comes to. The prose is generated, as everything in these tests is.
@MainActor
struct ChapterSelectionTests {
    private static let prose = """
        Дом стоял на краю деревни, и дорога от него уходила прямо в лес. \
        Утром там было тихо, только ветер качал верхушки старых сосен. \
        Мальчик вышел за ворота, посмотрел на небо и пошёл вниз по тропинке. \
        Вода в реке была холодной, а на другом берегу начинался густой туман.
        """

    private func layout() async -> ChapterLayout {
        await ChapterLayout.make(
            chapterId: 1,
            content: await ChapterContent.prepare(html: "<p>\(Self.prose)</p><p>\(Self.prose)</p>"),
            heading: ChapterHeading.make(position: 1, title: nil),
            context: JustificationTests.testContext
        )
    }

    /// A line of the body, with somewhere to put a finger on it.
    private struct Line {
        let middle: CGFloat
        let left: CGFloat
        let right: CGFloat
    }

    private func bodyLine(_ layout: ChapterLayout) throws -> Line {
        let all = layout.typesetLines
        let placed = layout.placedLines(onPage: 0)
        let found = try #require(
            placed.first { !all[$0.index].isHeading && all[$0.index].width > 200 },
            "no body line was set on the first page"
        )
        let start = layout.context.textRect.minX

        return Line(middle: found.edge + found.height / 2, left: start + 40, right: start + 150)
    }

    @Test
    func aPointOverAWordTakesTheWholeWord() async throws {
        let layout = await layout()
        let line = try bodyLine(layout)
        let range = try #require(layout.word(at: CGPoint(x: line.left, y: line.middle), onPage: 0))
        let picked = layout.selection(of: range)

        #expect(!picked.isEmpty)
        #expect(picked.words == 1)
        #expect(!picked.isPhrase)
        #expect(!picked.text.contains(" "), "\(picked.text) is more than one word")
    }

    @Test
    func aDragAcrossWordsTakesAllOfThem() async throws {
        let layout = await layout()
        let line = try bodyLine(layout)
        let range = try #require(layout.words(
            from: CGPoint(x: line.left, y: line.middle),
            to: CGPoint(x: line.right, y: line.middle),
            onPage: 0
        ))
        let picked = layout.selection(of: range)

        #expect(picked.isPhrase, "\(picked.text) came back as one word")
        #expect(picked.words > 1)
    }

    /// A finger dragged back the way it came picks the same words.
    @Test
    func aDragReadsTheSameBothWays() async throws {
        let layout = await layout()
        let line = try bodyLine(layout)
        let start = CGPoint(x: line.left, y: line.middle)
        let end = CGPoint(x: line.right, y: line.middle)

        let forwards = layout.words(from: start, to: end, onPage: 0)
        let backwards = layout.words(from: end, to: start, onPage: 0)

        #expect(forwards == backwards)
    }

    /// A drag opens out to whole words: it never stops in the middle of one.
    @Test
    func aDragEndsOnWordsRatherThanLetters() async throws {
        let layout = await layout()
        let line = try bodyLine(layout)
        let range = try #require(layout.words(
            from: CGPoint(x: line.left + 3, y: line.middle),
            to: CGPoint(x: line.right + 3, y: line.middle),
            onPage: 0
        ))
        let wider = try #require(layout.words(
            from: CGPoint(x: line.left, y: line.middle),
            to: CGPoint(x: line.right, y: line.middle),
            onPage: 0
        ))

        // Two points a few points apart inside the same pair of words come to the same words.
        #expect(range == wider)
    }

    /// The typesetter's own marks are not part of what the reader picked.
    @Test
    func whatIsPickedIsWhatWasWritten() async throws {
        let layout = await layout()
        let line = try bodyLine(layout)
        let range = try #require(layout.words(
            from: CGPoint(x: line.left, y: line.middle),
            to: CGPoint(x: line.right, y: line.middle),
            onPage: 0
        ))
        let picked = layout.selection(of: range)

        #expect(!picked.text.contains("\u{00AD}"), "a soft hyphen came through")
        #expect(!picked.text.contains("\u{2060}"), "a word joiner came through")
    }

    @Test
    func aStretchOnOneLineIsOneBox() async throws {
        let layout = await layout()
        let line = try bodyLine(layout)
        let range = try #require(layout.words(
            from: CGPoint(x: line.left, y: line.middle),
            to: CGPoint(x: line.right, y: line.middle),
            onPage: 0
        ))
        let boxes = layout.rects(of: range, onPage: 0)

        #expect(boxes.count == 1)
        #expect((boxes.first?.width ?? 0) > 0)
        #expect((boxes.first?.height ?? 0) > 0)
    }

    /// A drag down the page runs through several lines, and each one is painted on its own.
    @Test
    func aStretchDownThePageIsABoxPerLine() async throws {
        let layout = await layout()
        let all = layout.typesetLines
        let placed = layout.placedLines(onPage: 0)
        let body = placed.filter { !all[$0.index].isHeading && all[$0.index].width > 200 }

        try #require(body.count >= 3, "the page is too short to drag down")

        let start = layout.context.textRect.minX + 40
        let range = try #require(layout.words(
            from: CGPoint(x: start, y: body[0].edge + body[0].height / 2),
            to: CGPoint(x: start + 100, y: body[2].edge + body[2].height / 2),
            onPage: 0
        ))

        #expect(layout.rects(of: range, onPage: 0).count >= 3)
    }
}
