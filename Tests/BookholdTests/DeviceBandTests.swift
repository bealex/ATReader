//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import Testing

@testable import Bookhold

/// Where the reader's controls stand, from the edge the system keeps its vertical bar on, and what
/// that bar's column means to the page.
struct DeviceBandTests {
    private func insets(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0)
        -> EdgeInsets
    {
        EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing)
    }

    @Test
    func standsAcrossTheTopWhereTheSystemKeepsNoVerticalBar() {
        #expect(DeviceBand(barEdge: nil) == .top)
    }

    @Test
    func followsTheSystemsBarDownEitherSide() {
        #expect(DeviceBand(barEdge: .leading) == .leading)
        #expect(DeviceBand(barEdge: .trailing) == .trailing)
    }

    @Test
    func hangsTheControlsOffTheEdgeItFound() {
        #expect(DeviceBand.top.alignment == .top)
        #expect(DeviceBand.trailing.alignment == .trailing)
        #expect(DeviceBand.leading.isDownASide)
        #expect(!DeviceBand.top.isDownASide)
    }

    /// The bar goes away with the controls, so its column is the page's to fill.
    @Test
    func leavesTheBarsColumnOutOfThePagesInsets() {
        let unfolded = insets(leading: 8, bottom: 34, trailing: 84)

        #expect(DeviceBand.trailing.pageInsets(from: unfolded) == insets(leading: 8, bottom: 34))
        #expect(DeviceBand.leading.pageInsets(from: unfolded) == insets(bottom: 34, trailing: 84))
    }

    /// A phone on its side has the sensor housing down one edge, which is not a bar and is kept clear.
    @Test
    func keepsEveryInsetWithNoBarDownASide() {
        let turned = insets(leading: 59, bottom: 21, trailing: 59)

        #expect(DeviceBand.top.pageInsets(from: turned) == turned)
    }
}
