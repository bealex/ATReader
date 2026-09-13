//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookRenderer
import Testing
import UIKit

@testable import Bookhold

/// Titles standing together, and the air the block keeps around itself.
@MainActor
struct TitleBlockTests {
    // MARK: - What a block is

    @Test
    func touchingTitlesAreOneBlockAndTakeTheBiggestOne() {
        let levels: [Int?] = [ nil, 1, 3, 2, nil, nil, 4, nil ]

        #expect(TitleBlock.opening(levels) == [ nil, 1, nil, nil, nil, nil, 4, nil ])
        #expect(TitleBlock.closing(levels) == [ false, false, false, true, false, false, true, false ])
    }

    @Test
    func aBlockAtEitherEndIsStillABlock() {
        #expect(TitleBlock.opening([ 2, nil ]) == [ 2, nil ])
        #expect(TitleBlock.closing([ nil, 2 ]) == [ false, true ])
    }

    @Test
    func theAirGoesByLevel() {
        #expect(TitleBlock.air(forLevel: 1) == 8)
        #expect(TitleBlock.air(forLevel: 2) == 6)
        #expect(TitleBlock.air(forLevel: 3) == 3)
        #expect(TitleBlock.air(forLevel: 4) == 1)
        #expect(TitleBlock.air(forLevel: 9) == 1)
    }

    /// Two lines under a block that stands in air, and none under one that merely breaks the run.
    @Test
    func theGapUnderFollowsTheAirAbove() {
        #expect(TitleBlock.gap(after: 12) == 2)
        #expect(TitleBlock.gap(after: 3) == 2)
        #expect(TitleBlock.gap(after: 1) == 0)
        #expect(TitleBlock.gap(after: 0) == 0)
    }

    // MARK: - What the markup gives

    @Test
    func aHeadingElementSaysItsOwnLevel() {
        let read = BookHTML.paragraphs(from: "<p>Текст.</p><h2>Часть</h2><h4>Мелкий</h4>")

        #expect(read.map(\.titleLevel) == [ nil, 2, 4 ])
        #expect(read[1].text == "Часть")
    }

    /// A row of stars is a title because the book wrote it as one, not because of the characters in
    /// it. Centred is not a level: an epigraph and a dedication are centred too.
    @Test
    func aRowOfStarsIsNoTitleOnItsOwn() {
        let guessed = BookHTML.paragraphs(from: "<p>Текст.</p><p style=\"text-align:center\">⁂</p>")
        let written = BookHTML.paragraphs(from: "<p>Текст.</p><h2>⁂</h2>")

        #expect(guessed.map(\.titleLevel) == [ nil, nil ])
        #expect(written.map(\.titleLevel) == [ nil, 2 ])
    }

    @Test
    func ordinaryCentredTextIsNoTitle() {
        let read = BookHTML.paragraphs(from: "<p style=\"text-align:center\">Посвящается кому-то</p>")

        #expect(read.map(\.titleLevel) == [ nil ])
    }

    // MARK: - What the page does with it

    /// A subtitle takes six lines above it and two below, measured against an ordinary paragraph.
    @Test
    func aSubtitleStandsInItsAir() async {
        let plain = await layout(of: "<p>Один</p><p>Два</p><p>Три</p>")
        let titled = await layout(of: "<p>Один</p><h2>Два</h2><p>Три</p>")
        let line = Self.context.style.pageLine

        guard
            let ordinary = plain.typesetLines.first(where: { $0.text.hasPrefix("Два") }),
            let title = titled.typesetLines.first(where: { $0.text.hasPrefix("Два") })
        else {
            Issue.record("the chapter did not come out as three paragraphs")
            return
        }

        let air = (TitleBlock.air(forLevel: 2) + TitleBlock.gap(after: TitleBlock.air(forLevel: 2))) * line

        #expect(abs(title.height - ordinary.height - air) < 0.5)
    }

    /// The air stands over the title rather than under it.
    ///
    /// A page draws every line at its own baseline and then steps on by its height, so air the
    /// baseline knows nothing about lands under the words: the gap came out after the stars and there
    /// was none before them.
    @Test
    func theAirStandsOverTheTitle() async {
        let titled = await layout(of: "<p>Один</p><h2>Два</h2><p>Три</p>")
        let line = Self.context.style.pageLine

        guard
            let ordinary = titled.typesetLines.first(where: { $0.text.hasPrefix("Один") }),
            let title = titled.typesetLines.first(where: { $0.text.hasPrefix("Два") })
        else {
            Issue.record("the chapter did not come out as three paragraphs")
            return
        }

        #expect(abs(title.baseline - ordinary.baseline - TitleBlock.air(forLevel: 2) * line) < 0.5)
    }

    /// A chapter's own heading keeps two lines of its air where the chapter starts a page: the twelve
    /// would push it a third of the way down, and none would leave it hard against the top edge.
    @Test
    func theHeadingKeepsTwoLinesAtTheTopOfItsOwnPage() async {
        let laid = await layout(of: "<p>Один</p><p>Два</p>")

        guard let first = laid.typesetLines.first else {
            Issue.record("the chapter came out empty")
            return
        }

        // What the rule says, against a chapter that runs on and keeps every line of its air. The air
        // is counted in the layout's own reference line, which is the type size and the spacing.
        let runsOn = await layout(of: "<p>Один</p><p>Два</p>", startOffset: Self.context.textSize.height * 0.2)
        let reference = Self.context.style.pageLine

        guard let carried = runsOn.typesetLines.first else {
            Issue.record("the running-on chapter came out empty")
            return
        }

        let cut = (TitleBlock.air(forLevel: 1) - TitleBlock.atTheTopOfAPage) * reference

        #expect(abs(carried.height - first.height - cut) < 0.5, "the heading kept the wrong amount of air")
    }

    /// A title's air falls off the head of a page, so the break goes before the air instead.
    @Test(arguments: 1 ... 10)
    func noPageOpensOnATitleThatStandsInAir(after paragraphs: Int) async {
        let body = JustificationTests.prose(paragraphs)
            .components(separatedBy: "\n")
            .map { "<p>\($0)</p>" }
            .joined()
        let rest = JustificationTests.prose(4)
            .components(separatedBy: "\n")
            .map { "<p>\($0)</p>" }
            .joined()
        let laid = await layout(of: body + "<h2>Часть вторая</h2>" + rest)

        for page in 0 ..< laid.pageCount {
            guard let first = laid.typesetLines(onPage: page).first else { continue }

            #expect(first.text.hasPrefix("Часть вторая") == false, "page \(page) opened on a title")
        }
    }

    private static var context: ChapterLayout.Context { JustificationTests.testContext }

    private func layout(of html: String, startOffset: CGFloat = 0) async -> ChapterLayout {
        await ChapterLayout.make(
            chapterId: 1,
            content: await ChapterContent.prepare(html: html),
            heading: ChapterHeading.make(position: 1, title: nil),
            context: Self.context,
            startOffset: startOffset
        )
    }
}
