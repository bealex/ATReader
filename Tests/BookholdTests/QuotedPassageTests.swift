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
        // Held four parts at the near edge to one at the far, so it reads as moved over rather than
        // as text that was narrowed.
        let far = Self.context.textSize.width - (lines.filter { $0.origin > ordinary.origin }.map(\.width).max() ?? 0)

        #expect(quoted.origin > far * 3, "a quoted passage is not set over towards the far edge")

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

    /// A line of verse too long for the measure runs over to the far edge, so what is left of it reads
    /// as the rest of that line rather than as the next line of the poem.
    @Test
    func aVerseRunoverStandsAgainstTheFarEdge() async {
        let laid = await layout(of: "<p data-verse=\"1\">\(Self.filler)</p>")
        let lines = laid.typesetLines

        guard
            let opening = lines.first, lines.count > 1
        else {
            Issue.record("the verse line did not run over")
            return
        }

        let edge = Self.context.textSize.width
        let runovers = lines.dropFirst()

        #expect(runovers.allSatisfy { abs($0.width - edge) < 1 }, "a runover misses the far edge")
        // Verse is not justified, so the line it ran over from stops where its words stop. That is what
        // makes the runover read as the rest of that line rather than as the next one.
        #expect(opening.width < edge - 1, "the line was stretched to the measure like prose")
    }

    /// An ordinary paragraph still wraps the way prose does, which is what verse is being told from.
    @Test
    func aProseParagraphWrapsAtTheNearEdge() async {
        let laid = await layout(of: "<p>\(Self.filler)</p>")
        let lines = laid.typesetLines

        guard
            let opening = lines.first, lines.count > 1
        else {
            Issue.record("the paragraph did not wrap")
            return
        }

        #expect(lines.dropFirst().allSatisfy { $0.origin <= opening.origin })
    }

    /// The name under a quotation stands at the far edge of that quotation, not at the edge of the page:
    /// it is set against the passage it names, which is held off both edges.
    @Test
    func aQuotationsSourceStandsAtItsFarEdge() async {
        let laid = await layout(
            of: "<p data-inset=\"1\">\(Self.filler)</p><p data-source=\"1\" data-inset=\"1\"><em>Некто</em></p>"
        )

        guard
            let source = laid.typesetLines.last, let quoted = laid.typesetLines.first
        else {
            Issue.record("the chapter did not come out as two paragraphs")
            return
        }

        // Set against the far edge, not where the quotation starts. The quotation's own lines are no
        // yardstick for it: a justified one hangs its punctuation past the measure.
        #expect(source.origin > quoted.origin, "the name stands where the words it names do")
        #expect(source.width < Self.context.textSize.width, "the name reached past the quotation to the page")
    }

    /// The verse mark has to survive preparation, which rebuilds every block to move its marks onto the
    /// bound and hyphenated text. A field left out of that rebuild is dropped in silence.
    @Test
    func carriesTheVerseMarkThroughToThePage() async {
        let content = await ChapterContent.prepare(html: "<p data-verse=\"1\">Один два</p>")

        #expect(content.paragraphs.first?.isVerse == true)
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
