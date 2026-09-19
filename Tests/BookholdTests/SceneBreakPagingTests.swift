//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import CoreGraphics
import Foundation
import Testing

@testable import BookRenderer

/// A scene break divides what stands above it from what stands below, so no page opens on one: at the
/// head of a page the page break has already done the dividing and the marks say nothing.
struct SceneBreakPagingTests {
    private static let line: CGFloat = 20

    private func slug(_ index: Int, height: CGFloat = line, isBreak: Bool = false, isImage: Bool = false)
        -> PageCutter.Slug
    {
        PageCutter.Slug(
            characters: NSRange(location: index * 10, length: isImage ? 1 : 10),
            height: height,
            leastHeight: isImage ? height - height * ChapterLayout.Rules.plateGivesUp : height,
            titleAir: 0,
            startsParagraph: true,
            endsParagraph: true,
            endsWithHyphen: false,
            isHeading: false,
            isImage: isImage,
            isSceneBreak: isBreak
        )
    }

    private func cut(_ slugs: [PageCutter.Slug], depth: CGFloat) -> CutPages {
        let cutter = PageCutter(slugs: slugs, depth: depth, pageLine: Self.line, referenceLineHeight: Self.line)

        return cutter.cutFromTheStart()
    }

    private func opensOnABreak(_ laid: CutPages, _ slugs: [PageCutter.Slug]) -> Bool {
        laid.pages.dropFirst().contains { slugs[$0.lines.lowerBound].isSceneBreak }
    }

    /// Wherever the break falls against the page, it never ends up at the top of one.
    @Test
    func neverOpensAPageOnASceneBreak() {
        for at in 12 ... 18 {
            var slugs = (0 ..< 40).map { slug($0) }

            slugs[at] = slug(at, isBreak: true)

            let laid = cut(slugs, depth: 300)

            #expect(!opensOnABreak(laid, slugs), "a page opened on the break at \(at)")
        }
    }

    /// The reported page: text, a plate too tall for the room left, and the break that closes the scene.
    /// The plate gives up depth so all three finish one page, rather than the break opening the next.
    @Test
    func keepsTheBreakWithThePlateItFollows() {
        let slugs = (0 ..< 5).map { slug($0) } + [ slug(5, height: 260, isImage: true), slug(6, isBreak: true) ]
        let laid = cut(slugs, depth: 300)

        #expect(laid.pages.count == 1)
        #expect(laid.pages.first?.lines == 0 ..< 7)
        #expect(laid.pages.first?.plate?.line == 5)
    }

    /// Nothing is dragged about where the break already sits comfortably inside a page.
    @Test
    func leavesABreakInTheMiddleOfAPageAlone() {
        var slugs = (0 ..< 40).map { slug($0) }

        slugs[5] = slug(5, isBreak: true)

        let laid = cut(slugs, depth: 300)

        #expect(laid.pages.first?.lines.contains(5) == true)
        #expect(!opensOnABreak(laid, slugs))
    }

    /// A chapter opening on one has no page before it to move it to, and must still be cut.
    @Test
    func cutsAChapterThatOpensOnABreak() {
        var slugs = (0 ..< 40).map { slug($0) }

        slugs[0] = slug(0, isBreak: true)

        let laid = cut(slugs, depth: 300)

        #expect(!laid.pages.isEmpty)
        #expect(laid.pages.first?.lines.lowerBound == 0)
    }
}
