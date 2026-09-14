//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import CoreGraphics
import Foundation
import Testing

@testable import BookRenderer

/// A plate that will not fit the room left on a page gives up depth to finish it rather than taking a
/// page of its own and leaving the one before it half empty.
struct PlateFittingTests {
    private static let line: CGFloat = 20

    private func text(_ index: Int) -> PageCutter.Slug {
        PageCutter.Slug(
            characters: NSRange(location: index * 10, length: 10),
            height: Self.line,
            leastHeight: Self.line,
            titleAir: 0,
            startsParagraph: true,
            endsParagraph: true,
            endsWithHyphen: false,
            isHeading: false,
            isImage: false
        )
    }

    /// A plate whose whole depth is the picture, so what it may give up is the rule's own share of it.
    private func plate(_ index: Int, deep: CGFloat) -> PageCutter.Slug {
        PageCutter.Slug(
            characters: NSRange(location: index * 10, length: 1),
            height: deep,
            leastHeight: deep - deep * ChapterLayout.Rules.plateGivesUp,
            titleAir: 0,
            startsParagraph: true,
            endsParagraph: true,
            endsWithHyphen: false,
            isHeading: false,
            isImage: true
        )
    }

    private func cut(_ slugs: [PageCutter.Slug], depth: CGFloat) -> PageCutter.Cut {
        let cutter = PageCutter(slugs: slugs, depth: depth, pageLine: Self.line, referenceLineHeight: Self.line)

        return cutter.cut(from: 0, using: cutter.search())
    }

    /// The case that was reported: five lines and a plate that wants more room than is left.
    @Test
    func standsAPlateOnThePageItsTextIsOn() {
        let slugs = (0 ..< 5).map(text) + [ plate(5, deep: 260) ]
        let laid = cut(slugs, depth: 300)

        #expect(laid.pages.count == 1)
        #expect(laid.pages.first?.lines == 0 ..< 6)
    }

    @Test
    func givesUpOnlyWhatTheRoomAsksFor() {
        let slugs = (0 ..< 5).map(text) + [ plate(5, deep: 260) ]
        let laid = cut(slugs, depth: 300)
        let plate = laid.pages.first?.plate

        #expect(plate?.line == 5)
        // Five lines of twenty leave the plate the rest of the page, the squeeze the gaps allow aside.
        #expect((plate?.height ?? 0) < 260)
        #expect((plate?.height ?? 0) > 260 - 260 * ChapterLayout.Rules.plateGivesUp)
    }

    /// Past the floor a plate is small enough to read as a different picture, so it keeps its own page
    /// and the page before it stays short.
    @Test
    func keepsAPlateWholeWhereTheRoomWouldCostItTooMuch() {
        let slugs = (0 ..< 5).map(text) + [ plate(5, deep: 260) ]
        let laid = cut(slugs, depth: 200)

        #expect(laid.pages.count == 2)
        #expect(laid.pages.last?.lines == 5 ..< 6)
        #expect(laid.pages.last?.plate == nil)
    }

    /// A plate standing alone already has the whole page, and one too tall for even that gave up width
    /// when it was measured.
    @Test
    func leavesAPlateOnAPageOfItsOwnAlone() {
        let laid = cut([ plate(0, deep: 500) ], depth: 300)

        #expect(laid.pages.count == 1)
        #expect(laid.pages.first?.plate == nil)
    }

    /// Text gives up nothing, or a page would quietly set its own lines shorter than the column did.
    @Test
    func neverShortensText() {
        let laid = cut((0 ..< 40).map(text), depth: 300)

        #expect(laid.pages.allSatisfy { $0.plate == nil })
        #expect(laid.pages.count > 1)
    }

    /// The page the plate finishes is full, which is the whole point: no gap is left above it.
    @Test
    func leavesNoGapOnThePageThePlateFinishes() {
        let slugs = (0 ..< 5).map(text) + [ plate(5, deep: 260) ]
        let laid = cut(slugs, depth: 300)

        guard
            let page = laid.pages.first,
            let plate = page.plate
        else {
            Issue.record("the plate did not join the page")
            return
        }

        #expect(abs(Self.line * 5 + plate.height - 300) < 4)
    }
}
