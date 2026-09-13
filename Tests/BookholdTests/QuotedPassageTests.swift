//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookRenderer
import Testing
import UIKit

@testable import Bookhold

/// A passage a book holds off both edges, and a line it stands against the right one.
///
/// The text is generated nonsense: what is measured is where the lines fall, not what they say.
@MainActor
struct QuotedPassageTests {
    @Test
    func aQuotedPassageIsHeldOffBothEdges() async {
        let laid = await layout(of: "<p>\(Self.filler)</p><p data-inset=\"1\">\(Self.filler)</p>")
        let lines = laid.typesetLines

        guard
            let ordinary = lines.first, let quoted = lines.last, lines.count > 2
        else {
            Issue.record("the chapter did not come out as two paragraphs")
            return
        }

        #expect(quoted.origin > ordinary.origin, "a quoted passage starts no further in than the text")

        // A last line may stop anywhere, so the furthest each reaches is what says where its edge is.
        let held = lines.filter { $0.origin > ordinary.origin }
        let plain = lines.filter { $0.origin <= ordinary.origin }
        let reach = { (group: [ChapterLayout.TypesetLine]) in group.map(\.width).max() ?? 0 }

        #expect(reach(held) < reach(plain), "a quoted passage reaches as far as the text does")
    }

    @Test
    func aRightAlignedLineStandsAgainstTheRightEdge() async {
        let laid = await layout(of: "<p>\(Self.filler)</p><p style=\"text-align:right\">Один два</p>")

        guard
            let signature = laid.typesetLines.last, let body = laid.typesetLines.first
        else {
            Issue.record("the chapter did not come out as two paragraphs")
            return
        }

        let edge = Self.context.textSize.width

        // `width` is where the line ends, counted from the same edge its origin is.
        #expect(abs(signature.width - edge) < 1, "a right-set line misses the edge")
        #expect(body.origin < signature.origin, "the body was set against the right edge as well")
    }

    /// Long enough to wrap several times, so a paragraph has lines to compare.
    private static let filler = String(repeating: "Один два три четыре пять шесть семь. ", count: 6)

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
