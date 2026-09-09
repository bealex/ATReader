//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import DesignSystem
import Foundation
import SwiftUI
import Testing

/// The card and its pointer, which are one path.
///
/// Drawn as one so they cannot come out two colours and so a single shadow is cast by both, which is
/// what the system's own popover would not do. What is checked is that the pointer is on the right
/// side of the card and never wanders off it.
struct CalloutShapeTests {
    private static let box = CGRect(x: 0, y: 0, width: 300, height: 120)
    private static var band: CGFloat { CalloutShape.pointer.height }

    private static func path(pointsDown: Bool, pointerX: CGFloat = 150) -> Path {
        CalloutShape(pointerX: pointerX, pointsDown: pointsDown).path(in: box)
    }

    /// A card above what it points at reaches down to it, and its own body stops short of the bottom.
    @Test
    func aCardAboveReachesDownToItsPoint() {
        let path = Self.path(pointsDown: true)

        #expect(path.contains(CGPoint(x: 150, y: Self.box.maxY - 1)), "the pointer never reached the bottom")
        #expect(!path.contains(CGPoint(x: 20, y: Self.box.maxY - 1)), "the card ran on past where the pointer is")
        #expect(path.contains(CGPoint(x: 150, y: Self.box.maxY - Self.band - 4)), "the card stopped too soon")
    }

    /// And a card below reaches up instead.
    @Test
    func aCardBelowReachesUpToItsPoint() {
        let path = Self.path(pointsDown: false)

        #expect(path.contains(CGPoint(x: 150, y: Self.box.minY + 1)), "the pointer never reached the top")
        #expect(!path.contains(CGPoint(x: 20, y: Self.box.minY + 1)), "the card ran on past where the pointer is")
        #expect(path.contains(CGPoint(x: 150, y: Self.box.minY + Self.band + 4)), "the card started too late")
    }

    /// Whatever it is asked for, the shape keeps to the room it was given.
    @Test(arguments: [ -400.0, -1.0, 150.0, 301.0, 900.0 ])
    func aShapeKeepsToItsBox(pointerX: CGFloat) {
        let bounds = Self.path(pointsDown: true, pointerX: pointerX).boundingRect

        #expect(bounds.minX >= Self.box.minX - 0.5)
        #expect(bounds.maxX <= Self.box.maxX + 0.5)
        #expect(bounds.minY >= Self.box.minY - 0.5)
        #expect(bounds.maxY <= Self.box.maxY + 0.5)
    }

    /// A pointer asked for off the end of the card is brought back onto its straight edge, so it never
    /// grows out of a rounded corner.
    @Test
    func aPointerIsKeptClearOfTheCorners() {
        let path = Self.path(pointsDown: true, pointerX: -400)
        // As far left as a pointer may stand: clear of the rounded corner, and clear of its own width.
        let tip = Design.Radius.medium + CalloutShape.pointer.width / 2

        #expect(path.contains(CGPoint(x: tip, y: Self.box.maxY - 1)), "the pointer was pushed off the card")
        #expect(
            !path.contains(CGPoint(x: Self.box.minX + 1, y: Self.box.maxY - 1)),
            "the pointer grew out of the corner"
        )
    }
}

/// Several boxes are one thing for an aside to stand clear of.
struct CalloutBoxTests {
    @Test
    func nothingCoversNothing() {
        #expect(CalloutPlacement.bounds(around: []) == nil)
    }

    @Test
    func oneBoxIsItself() {
        let one = CGRect(x: 10, y: 20, width: 30, height: 40)

        #expect(CalloutPlacement.bounds(around: [ one ]) == one)
    }

    /// Words picked across three lines are three boxes and one thing.
    @Test
    func severalBoxesCoverAllOfThemselves() {
        let lines = [
            CGRect(x: 40, y: 100, width: 200, height: 20),
            CGRect(x: 10, y: 130, width: 260, height: 20),
            CGRect(x: 10, y: 160, width: 90, height: 20),
        ]
        let around = CalloutPlacement.bounds(around: lines)

        #expect(around == CGRect(x: 10, y: 100, width: 260, height: 80))
    }
}
