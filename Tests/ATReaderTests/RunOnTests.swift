//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import Testing
import UIKit

@testable import ATReader

/// A chapter may finish the page the one before it ended on, but only if it brings a few lines of
/// itself along. A heading with nothing under it, or a line or two, is a title stranded at the foot of
/// the page, and the chapter belongs on a page of its own.
///
/// The free space cannot answer this on its own: it is measured in body lines, and a heading stands far
/// taller than those, so a gap that looks like six lines can hold a heading and nothing else. These
/// check the count the rule actually reads.
@MainActor
struct RunOnTests {
    static let context = JustificationTests.testContext

    private func layout(startOffset: CGFloat) async -> ChapterLayout {
        await ChapterLayout.make(
            chapterId: 1,
            content: await ChapterContent.prepare(html: "<p>\(JustificationTests.words(120))</p>"),
            heading: ChapterHeading.make(position: 3, title: "Часть третья"),
            context: Self.context,
            startOffset: startOffset
        )
    }

    /// A chapter starting a page of its own always brings its text with it.
    @Test
    func aChapterOnItsOwnPageCarriesItsText() async {
        let layout = await layout(startOffset: 0)

        #expect(layout.bodyLineCount(onPage: 0) >= BookPagination.runOnLineMinimum)
    }

    /// The case in the screenshot: a gap deep enough to look inviting, which the heading fills on its
    /// own. The count has to come back below the minimum so the chapter is moved off the shared page.
    @Test(arguments: [ 30.0, 60.0, 90.0 ])
    func aGapThatOnlyFitsAHeadingBringsTooFewLines(free: CGFloat) async {
        let offset = Self.context.textSize.height - free
        let layout = await layout(startOffset: offset)

        #expect(
            layout.bodyLineCount(onPage: 0) < BookPagination.runOnLineMinimum,
            "\(Int(free))pt held \(layout.bodyLineCount(onPage: 0)) lines, so the chapter would run on"
        )
    }

    /// Given real room, a chapter is allowed to share the page.
    @Test
    func aDeepGapLetsTheChapterRunOn() async {
        let layout = await layout(startOffset: Self.context.textSize.height * 0.45)

        #expect(layout.bodyLineCount(onPage: 0) >= BookPagination.runOnLineMinimum)
    }
}
