//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import CoreGraphics
import Testing

@testable import DesignSystem

/// A cover turned open: flat at both ends of the turn, curled with its free edge leading in between.
struct LeafTests {
    private func freeEdge(of leaf: Leaf, strips count: Int = 24) -> (across: CGFloat, toward: CGFloat) {
        let last = leaf.strips(count).last!

        return (last.across + last.length * cos(last.angle), last.toward + last.length * sin(last.angle))
    }

    @Test
    func liesFlatOverTheHingeBeforeTheTurn() {
        let leaf = Leaf(width: 300, turned: 0)
        let edge = freeEdge(of: leaf)

        #expect(leaf.strips(24).allSatisfy { $0.angle == 0 })
        #expect(abs(edge.across - 300) < 0.001)
        #expect(abs(edge.toward) < 0.001)
    }

    @Test
    func liesFlatOnTheFarSideOnceTurned() {
        let leaf = Leaf(width: 300, turned: 1)
        let edge = freeEdge(of: leaf)

        #expect(leaf.strips(24).allSatisfy { abs($0.angle - .pi) < 0.001 })
        #expect(abs(edge.across + 300) < 0.001)
        #expect(abs(edge.toward) < 0.001)
    }

    /// The free edge is lifted first, so every strip has turned at least as far as the one before it.
    @Test
    func theFreeEdgeLeads() {
        for turned in stride(from: CGFloat(0.1), through: 0.9, by: 0.1) {
            let angles = Leaf(width: 300, turned: turned).strips(24).map(\.angle)

            #expect(zip(angles, angles.dropFirst()).allSatisfy { $0 <= $1 })
            #expect(angles.last! > angles.first!, "a sheet halfway over is lying flat")
        }
    }

    /// Bending never stretches the sheet: its strips add up to its width whatever the turn.
    @Test
    func keepsItsWidth() {
        for turned in stride(from: CGFloat(0), through: 1, by: 0.25) {
            let strips = Leaf(width: 300, turned: turned).strips(24)

            #expect(abs(strips.map(\.length).reduce(0, +) - 300) < 0.001)
            #expect(strips.first?.cut.lowerBound == 0)
            #expect(strips.last?.cut.upperBound == 1)
        }
    }

    @Test
    func showsItsFrontBeforeTheTurnAndItsBackAfter() {
        let hinge = CGPoint(x: -150, y: 0)

        for (turned, front) in [ (CGFloat(0), true), (1, false) ] {
            let leaf = Leaf(width: 300, turned: turned)

            #expect(leaf.strips(8).allSatisfy { leaf.showsFront(of: $0, hinge: hinge, distance: 1_000) == front })
        }
    }
}
