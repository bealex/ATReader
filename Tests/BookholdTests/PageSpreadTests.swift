//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookRenderer
import CoreGraphics
import SwiftUI
import Testing

/// Which devices read as one page and which as two, and where a spread puts them.
struct PageSpreadTests {
    private static let phone = CGSize(width: 393, height: 852)
    private static let phoneOnItsSide = CGSize(width: 956, height: 440)
    private static let pad = CGSize(width: 834, height: 1194)
    private static let padOnItsSide = CGSize(width: 1194, height: 834)
    private static let smallPad = CGSize(width: 744, height: 1133)

    private func spread(_ sheet: CGSize, safeArea: EdgeInsets = EdgeInsets(), margins: Double = 24) -> PageSpread {
        PageSpread(sheet: sheet, safeArea: safeArea, margins: margins)
    }

    private func bands(top: CGFloat, sides: CGFloat = 0, bottom: CGFloat) -> EdgeInsets {
        EdgeInsets(top: top, leading: sides, bottom: bottom, trailing: sides)
    }

    /// The widest a page ever comes out, which is the longest measure the spread allows. The margins
    /// are taken out of that measure rather than added around it, so they never widen the page.
    private static let widestPage: CGFloat = 440

    @Test
    func standsOnePageOnAPhone() {
        let one = spread(Self.phone, safeArea: bands(top: 59, bottom: 34))

        #expect(one.columns == 1)
        #expect(one.pageSize.width == Self.phone.width)
        #expect(one.inset == 0)
    }

    /// The page a phone has always set, to the point. A page measured any differently would re-measure
    /// every book on every phone the moment it updated.
    @Test
    func leavesAPhoneExactlyAsItWas() {
        let one = spread(Self.phone, safeArea: bands(top: 59, bottom: 34))

        #expect(one.pageSize == Self.phone)
        #expect(one.pageSafeArea == bands(top: 59, bottom: 34))
        #expect(one.gutter == 0)
    }

    /// A large phone on its side has the width for two pages and the depth to keep them page-shaped,
    /// so it opens like a small book rather than running one line the whole way across.
    @Test
    func standsTwoPagesOnAPhoneTurnedOnItsSide() {
        let two = spread(Self.phoneOnItsSide, safeArea: bands(top: 0, sides: 59, bottom: 21))

        #expect(two.columns == 2)
        #expect(two.pageSize.width <= two.pageSize.height)
    }

    /// A window with the width for two pages and not the depth keeps one, held to a measure.
    @Test
    func keepsOnePageWhereTwoWouldComeOutLandscape() {
        let one = spread(CGSize(width: 1200, height: 380))

        #expect(one.columns == 1)
        #expect(one.pageSize.width == Self.widestPage)
    }

    @Test
    func centresTheOnePageItHoldsToAMeasure() {
        let sheet = CGSize(width: 1200, height: 380)
        let one = spread(sheet)

        #expect(one.inset == (sheet.width - one.pageSize.width) / 2)
    }

    /// An edge with no notch and no indicator behind it still keeps room for the running head, so the
    /// head and the page number are not one against the glass and the other lifted clear of it.
    @Test
    func keepsABandAtTheHeadAndFootWhereTheDeviceAsksForNone() {
        let laid = spread(Self.phoneOnItsSide, safeArea: bands(top: 0, sides: 59, bottom: 21))

        #expect(laid.pageSafeArea.top >= 20)
        #expect(laid.pageSafeArea.bottom == 21)
    }

    @Test
    func standsTwoPagesOnAPad() {
        for sheet in [ Self.pad, Self.padOnItsSide, Self.smallPad ] {
            let two = spread(sheet, safeArea: bands(top: 24, bottom: 20))

            #expect(two.columns == 2)
            // The air between the columns is the two pages' own margins, the same margin the sides
            // have, so the gutter itself adds nothing to them unless they are too small for a binding.
            #expect(two.gutter + Self.margins * 2 >= Self.leastBinding)
        }
    }

    /// A reader who has turned the margins off altogether still gets the least a binding takes.
    @Test
    func partsTwoPagesWhereThereAreNoMarginsToPartThem() {
        let two = spread(Self.pad, safeArea: bands(top: 24, bottom: 20), margins: 0)

        #expect(two.columns == 2)
        #expect(two.gutter >= Self.leastBinding)
    }

    /// Widening the margins narrows the text rather than widening the page around it, on one column or
    /// two. A margin that left the measure alone is the one thing a margin may not do.
    @Test
    func theMarginsNarrowTheText() {
        for sheet in [ Self.phone, Self.pad, Self.padOnItsSide ] {
            let narrow = spread(sheet, margins: 8)
            let wide = spread(sheet, margins: 60)

            #expect(
                wide.pageSize.width - 60 * 2 < narrow.pageSize.width - 8 * 2,
                "the measure did not narrow on \(sheet)"
            )
        }
    }

    private static let margins: Double = 24
    private static let leastBinding: Double = 16

    /// Both pages are measured the same, or a chapter set for one would have to be set again for the
    /// other.
    @Test
    func measuresBothPagesAlike() {
        let two = spread(Self.pad, safeArea: bands(top: 24, bottom: 20))

        #expect(two.pageSafeArea.leading == 0)
        #expect(two.pageSafeArea.trailing == 0)
        #expect(two.origin(ofColumn: 1) - two.origin(ofColumn: 0) == two.pageSize.width + two.gutter)
    }

    @Test
    func laysTheSpreadOutSymmetrically() {
        let two = spread(Self.pad, safeArea: bands(top: 24, bottom: 20))
        let taken = two.pageSize.width * 2 + two.gutter

        #expect(two.inset == (Self.pad.width - taken) / 2)
        #expect(two.origin(ofColumn: 1) + two.pageSize.width == Self.pad.width - two.inset)
    }

    /// A pad given a third of the screen is a phone, and reads like one.
    @Test
    func putsANarrowWindowBackToOnePage() {
        #expect(spread(CGSize(width: 375, height: 1194)).columns == 1)
        #expect(spread(CGSize(width: 570, height: 834)).columns == 1)
    }

    /// Margins are the reader's, and a reader who wants them wide enough wants one page.
    @Test
    func putsAPadBackToOnePageUnderWideMargins() {
        #expect(spread(Self.pad, margins: 100).columns == 1)
    }

    @Test
    func neverRunsAPageWiderThanTheMeasureAllows() {
        for sheet in [ Self.phone, Self.phoneOnItsSide, Self.pad, Self.padOnItsSide, CGSize(width: 1024, height: 1366) ] {
            let laid = spread(sheet)

            #expect(laid.pageSize.width <= Self.widestPage)
        }
    }

    @Test
    func findsThePageAPointLandedOn() {
        let two = spread(Self.pad, safeArea: bands(top: 24, bottom: 20))

        #expect(two.column(containing: two.origin(ofColumn: 0) + 10) == 0)
        #expect(two.column(containing: two.origin(ofColumn: 1) + 10) == 1)
        // The binding belongs to the page after it, the way a gap between words does.
        #expect(two.column(containing: two.origin(ofColumn: 1) - two.gutter / 4) == 1)
    }

    @Test
    func carriesAPointOntoItsPageAndARectangleBack() {
        let two = spread(Self.pad, safeArea: bands(top: 24, bottom: 20))
        let point = CGPoint(x: two.origin(ofColumn: 1) + 30, y: 100)

        #expect(two.onPage(point, column: 1) == CGPoint(x: 30, y: 100))
        #expect(two.onSheet(CGRect(x: 30, y: 100, width: 5, height: 5), column: 1).minX == point.x)
    }

    @Test
    func givesAPhoneOnlyOneColumnToFindAPointIn() {
        let one = spread(Self.phone, safeArea: bands(top: 59, bottom: 34))

        #expect(one.column(containing: 0) == 0)
        #expect(one.column(containing: Self.phone.width - 1) == 0)
    }
}
