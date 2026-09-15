//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import CoreGraphics
import SwiftUI

/// How one sheet of the reader is divided into pages: two side by side where there is room for two
/// that read, otherwise one held to a width the eye can track.
///
/// A page is measured, drawn and hit-tested in its own coordinates, so all this settles is how big one
/// page is and where on the sheet it stands. Nothing below it knows a spread exists.
///
/// The sides of the device's own safe area are spent outside the spread rather than in its gutter, so
/// both pages come out the same size and a chapter set for one is set for the other.
public struct PageSpread: Equatable, Sendable {
    /// How many pages stand on one sheet.
    public let columns: Int
    /// How big one of them is, which is what a chapter is measured against.
    public let pageSize: CGSize
    /// The device's own bands as one page takes them: the top and bottom of the sheet, and no sides.
    public let pageSafeArea: EdgeInsets
    /// Where the first page starts, measured from the leading edge of the sheet.
    public let inset: CGFloat
    /// The air between two pages, which is the binding of the book.
    public let gutter: CGFloat

    /// - Parameter textSize: the size the book is set at, which is what the measure is held against.
    public init(sheet: CGSize, safeArea: EdgeInsets, margins: Double, textSize: Double) {
        let room = sheet.width - safeArea.leading - safeArea.trailing
        let widest = Self.mostMeasure * textSize
        // A spread has three bands of air: the two edges and the binding. Both pages' margins meet in
        // the binding, so no band is narrower than two of them, and a reader who has turned the margins
        // off altogether still gets the least a binding needs.
        let leastAir = max(margins * 2, Self.leastAir)
        let paired = min(widest, (room - leastAir * 3) / 2)
        // A column too narrow to read is worth more as one page than as half a spread, and so is a pair
        // that came out landscape: that reads as a screen split down the middle rather than as a book.
        let twoUp = paired >= Self.leastMeasure * textSize && paired + margins * 2 <= sheet.height

        // A band of its own at the head and the foot, where the device leaves none. An edge with no
        // notch and no indicator behind it gave the running head four points of air and stood it against
        // the glass, while the foot kept the indicator's room and the page came out lopsided.
        pageSafeArea = EdgeInsets(
            top: max(safeArea.top, Self.leastBand),
            leading: 0,
            bottom: max(safeArea.bottom, Self.leastBand),
            trailing: 0
        )
        columns = twoUp ? 2 : 1

        // The margins act on the measure, not on the page: the text is what the sheet has room for less
        // the margins, held to a width the eye can track back across. So widening the margins narrows
        // the text rather than widening the page around it, which is the whole point of a margin.
        let measure = max(0, twoUp ? paired : min(widest, room) - margins * 2)
        // What the measure leaves over is parted between the bands, so the air at the edges of a spread
        // is the air in its binding and the two pages stand evenly on the sheet.
        let air = twoUp ? (room - measure * 2) / 3 : (room - measure) / 2

        pageSize = CGSize(width: measure + margins * 2, height: sheet.height)
        gutter = twoUp ? air - margins * 2 : 0
        inset = safeArea.leading + air - margins
    }

    /// Where one of the pages stands on the sheet.
    public func origin(ofColumn column: Int) -> CGFloat {
        inset + (pageSize.width + gutter) * CGFloat(column)
    }

    /// Which page a point on the sheet landed on.
    public func column(containing x: CGFloat) -> Int {
        guard columns > 1 else { return 0 }

        return x < origin(ofColumn: 1) - gutter / 2 ? 0 : 1
    }

    /// A point on the sheet, in the coordinates of the page it landed on.
    public func onPage(_ point: CGPoint, column: Int) -> CGPoint {
        CGPoint(x: point.x - origin(ofColumn: column), y: point.y)
    }

    /// A rectangle of a page, back in the sheet's own coordinates.
    public func onSheet(_ rect: CGRect, column: Int) -> CGRect {
        rect.offsetBy(dx: origin(ofColumn: column), dy: 0)
    }

    /// The narrowest column of text worth standing two of, in ems. Below this a spread reads as two
    /// gutters with words caught between them.
    private static let leastMeasure: CGFloat = 17

    /// The widest a page's text runs, in ems. Past it the eye loses the start of the next line on the
    /// way back across. Measured against the book's own size rather than in points, so a column holds
    /// the same number of characters however large the reader sets the text.
    private static let mostMeasure: CGFloat = 36

    /// The least room kept at the head and the foot of a page for its running head and page number,
    /// where the device itself asks for none.
    private static let leastBand: CGFloat = 20

    /// The least air at the side of a page, for a reader who has turned the margins off altogether.
    private static let leastAir: Double = 16
}
