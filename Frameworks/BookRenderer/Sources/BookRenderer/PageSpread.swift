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

    public init(sheet: CGSize, safeArea: EdgeInsets, margins: Double) {
        let room = sheet.width - safeArea.leading - safeArea.trailing
        // No gutter of its own beyond what the two pages' own margins already give: the air between the
        // columns is the same margin the sides have. A reader who has turned the margins off altogether
        // still gets the least a binding needs.
        let gutter = max(0, Self.leastGutter - margins * 2)
        let halved = (room - gutter) / 2
        let twoUp = halved - margins * 2 >= Self.leastMeasure && halved * Self.leastShape <= sheet.height

        // A band of its own at the head and the foot, where the device leaves none. An edge with no
        // notch and no indicator behind it gave the running head four points of air and stood it against
        // the glass, while the foot kept the indicator's room and the page came out lopsided.
        pageSafeArea = EdgeInsets(
            top: max(safeArea.top, Self.leastBand),
            leading: 0,
            bottom: max(safeArea.bottom, Self.leastBand),
            trailing: 0
        )
        self.gutter = twoUp ? gutter : 0
        columns = twoUp ? 2 : 1

        // The margins act on the measure, not on the page: the text is what the column has room for less
        // the margins, held to a width the eye can track back across. So widening the margins narrows
        // the text rather than widening the page around it, which is the whole point of a margin. What a
        // wide sheet has over is laid outside the spread, where a book's own widest margins are.
        let column = twoUp ? halved : room
        let width = min(Self.mostMeasure, column)
        let measure = width - margins * 2

        pageSize = CGSize(width: max(0, measure + margins * 2), height: sheet.height)
        inset = safeArea.leading + (room - width * CGFloat(columns) - self.gutter * CGFloat(columns - 1)) / 2
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

    /// The narrowest column of text worth standing two of. Below this a spread reads as two gutters
    /// with words caught between them.
    private static let leastMeasure: CGFloat = 260

    /// The widest a page's text runs. Past it the eye loses the start of the next line on the way back
    /// across.
    private static let mostMeasure: CGFloat = 440

    /// A page is never wider than it is tall. Two pages that each came out landscape would read as a
    /// screen split down the middle rather than as a book.
    private static let leastShape: CGFloat = 1

    /// The least room kept at the head and the foot of a page for its running head and page number,
    /// where the device itself asks for none.
    private static let leastBand: CGFloat = 20

    /// The least air between two pages, for a reader who has turned the margins off altogether.
    private static let leastGutter: Double = 16
}
