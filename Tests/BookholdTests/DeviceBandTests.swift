//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import Testing

@testable import Bookhold

/// Which edge the device keeps its own band on, read off the window's insets and its shape.
struct DeviceBandTests {
    private static let upright = CGSize(width: 834, height: 1194)
    private static let turned = CGSize(width: 1194, height: 834)
    private static let phone = CGSize(width: 393, height: 852)
    private static let phoneTurned = CGSize(width: 852, height: 393)

    private func insets(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0)
        -> EdgeInsets
    {
        EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing)
    }

    @Test
    func readsAPhoneHeldUprightAsABandAcrossTheTop() {
        #expect(DeviceBand.read(insets(top: 59, bottom: 34), in: Self.phone) == .top)
    }

    /// The case that must not move. Whatever a phone on its side reports at either edge, its band is at
    /// the head or the foot of the window rather than down a side, and the controls stay put.
    @Test
    func keepsAWindowOnItsSideAtTheTop() {
        #expect(DeviceBand.read(insets(leading: 59, bottom: 21, trailing: 59), in: Self.phoneTurned) == .top)
        #expect(DeviceBand.read(insets(leading: 59, bottom: 21), in: Self.phoneTurned) == .top)
        #expect(DeviceBand.read(insets(bottom: 21, trailing: 59), in: Self.turned) == .top)
    }

    @Test
    func findsABandDownEitherSideOfAnUprightWindow() {
        #expect(DeviceBand.read(insets(top: 12, leading: 4, bottom: 12, trailing: 59), in: Self.upright) == .trailing)
        #expect(DeviceBand.read(insets(top: 12, leading: 59, bottom: 12, trailing: 4), in: Self.upright) == .leading)
    }

    /// A rounded corner leaves a few points at each edge, which is not a band.
    @Test
    func takesARoundedCornerForNothing() {
        #expect(DeviceBand.read(insets(top: 24, leading: 8, bottom: 20), in: Self.upright) == .top)
    }

    @Test
    func countsASquareWindowAsUpright() {
        #expect(DeviceBand.read(insets(trailing: 59), in: CGSize(width: 900, height: 900)) == .trailing)
    }

    @Test
    func hangsTheControlsOffTheEdgeItFound() {
        #expect(DeviceBand.top.alignment == .top)
        #expect(DeviceBand.trailing.alignment == .trailing)
        #expect(DeviceBand.leading.isDownASide)
        #expect(!DeviceBand.top.isDownASide)
    }

    @Test
    func readsNoInsetsAtAllAsTheTop() {
        #expect(DeviceBand.read(EdgeInsets(), in: Self.upright) == .top)
    }
}
