//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookRenderer
import Testing
import UIKit

@testable import Bookhold

/// A line the book broke itself, which the column may not carry text across.
///
/// The text is generated nonsense: what is measured is where the lines fall, not what they say.
@MainActor
struct LineBreakTests {
    @Test
    func aBreakTheBookMadeEndsTheLine() async {
        let laid = await layout(of: "<p>Один два<br>Три четыре</p>")
        let lines = laid.typesetLines

        #expect(lines.count == 2, "the break did not end the line")
        #expect(lines.first?.text.contains("Один") == true)
        #expect(lines.last?.text.contains("Три") == true)
        // Neither line carries the other's words, which is the whole of the rule.
        #expect(lines.first?.text.contains("Три") == false)
    }

    /// A short line before a break is a line the book asked for, not one the column left wanting.
    @Test
    func theLineBeforeABreakIsNotStretched() async {
        let laid = await layout(of: "<p>Один два<br>\(Self.filler)</p>")

        guard
            let first = laid.typesetLines.first
        else {
            Issue.record("the chapter came out with no lines at all")
            return
        }

        #expect(!first.isJustified, "the line was stretched to the measure it never meant to reach")
        #expect(first.width < Self.context.textSize.width)
    }

    @Test
    func aParagraphWithoutOneIsStillSetAsOne() async {
        let laid = await layout(of: "<p>\(Self.filler)</p>")

        #expect(laid.typesetLines.count > 2)
        #expect(laid.typesetLines.dropLast().allSatisfy { !$0.endsParagraph })
    }

    private static let filler = String(repeating: "Один два три четыре пять шесть семь. ", count: 4)

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
