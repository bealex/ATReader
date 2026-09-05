//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
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

    /// A part title is a chapter of a heading and nothing else. It used to hold a page to itself and
    /// send the chapter after it to the next one, leaving most of a page empty.
    @Test
    func aChapterOfOnlyAHeadingLetsTheNextFollowIt() async {
        let layout = await ChapterLayout.make(
            chapterId: 1,
            content: await ChapterContent.prepare(html: ""),
            heading: ChapterHeading.make(position: 2, title: "Часть вторая"),
            context: Self.context
        )

        #expect(layout.pageCount == 1)
        #expect(BookPagination.startOffset(after: layout, context: Self.context) > 0, "the page after it is wasted")
    }

    /// Given real room, a chapter is allowed to share the page.
    @Test
    func aDeepGapLetsTheChapterRunOn() async {
        let layout = await layout(startOffset: Self.context.textSize.height * 0.45)

        #expect(layout.bodyLineCount(onPage: 0) >= BookPagination.runOnLineMinimum)
    }

    // MARK: - Two chapters on one page

    /// The reported page: the end of one chapter and the whole of the next drawn over the same lines.
    ///
    /// The reader lays the chapters either side of the one on screen out before they are needed, and
    /// took each one's offset from the book pass. A chapter the pass had not reached yet answered zero,
    /// the same as one that starts a page of its own, so it was set from the top of a page it in fact
    /// shares. What decides the stacking is therefore where the two layouts were actually set, which is
    /// what will be drawn, and a chapter set for its own page is never put on someone else's.
    @Test
    func aChapterSetForItsOwnPageIsNeverStackedOnAnother() async {
        // Short enough that most of its last page is left over, which is what a chapter runs on into.
        let previous = await layout(words: 40, startOffset: 0)
        let offset = BookPagination.startOffset(after: previous, context: Self.context)
        let runsOn = await layout(startOffset: offset)
        let ownPage = await layout(startOffset: 0)

        #expect(offset > 0, "the chapter leaves room for a neighbour on its last page")
        #expect(BookPagination.sharesLastPage(of: previous, with: runsOn, context: Self.context))
        #expect(
            !BookPagination.sharesLastPage(of: previous, with: ownPage, context: Self.context),
            "it would be drawn from the top of the page, over the chapter ending there"
        )
    }

    /// Where that wrong offset came from: reading ahead of the pass. An unmeasured chapter has no
    /// placement at all, so the reader has nothing to lay it out from until the pass reaches it.
    @Test
    func aChapterThePassHasNotReachedHasNoPlaceYet() async {
        let chapters = Self.book(of: 3)
        let pagination = Self.pagination()

        await pagination.measure(chapters: chapters, through: 1, content: Self.content)

        #expect(pagination.placement(of: chapters[0].id) != nil)
        #expect(pagination.placement(of: chapters[1].id) == nil, "the reader could lay it out at the wrong offset")

        await pagination.measure(chapters: chapters, through: chapters.count, content: Self.content)

        #expect(pagination.runsOn(chapters[1].id), "and the place it turns out to have is not the top of a page")
    }

    /// Chapters short enough that each one leaves room for the next on its last page.
    private static func book(of count: Int) -> [ChapterInfo] {
        (1 ... count).map {
            ChapterInfo(id: $0, workId: 1, title: "Глава \($0)", sortOrder: $0, textLength: nil)
        }
    }

    private static let content: BookPagination.ContentProvider = { _ in
        await ChapterContent.prepare(html: "<p>\(JustificationTests.words(40))</p>")
    }

    /// A pass over a store with nothing in it, so every chapter is measured rather than read back.
    private static func pagination() -> BookPagination {
        BookPagination.make(
            workId: 1,
            context: context,
            store: LocalStore(
                fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("run-on-\(UUID().uuidString).sqlite")
            )
        )
    }
}
