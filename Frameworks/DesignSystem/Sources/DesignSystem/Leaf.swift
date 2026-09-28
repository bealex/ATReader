//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import QuartzCore

/// A thin sheet hinged along its leading edge, turned over onto the far side and bending as it goes.
///
/// A sheet this thin is lifted by its free edge, so that edge leads and the sheet curls on the way over;
/// it lies flat at both ends. The sheet is cut into strips across its width, each flat, each at its own
/// angle, laid end to end from the hinge.
public struct Leaf {
    /// How wide the sheet is, from the hinge to its free edge.
    public let width: CGFloat
    /// How far over it has turned: none of it lies flat over the hinge's own side, all of it flat on the far one.
    public let turned: CGFloat

    public init(width: CGFloat, turned: CGFloat) {
        self.width = width
        self.turned = min(max(turned, 0), 1)
    }

    /// One flat piece of the sheet: where its leading edge stands from the hinge, towards the eye, and at
    /// what angle it runs from there.
    public struct Strip {
        public let across: CGFloat
        public let toward: CGFloat
        public let angle: CGFloat
        public let length: CGFloat
        /// Which part of the sheet's width this strip is cut from, as fractions of it.
        public let cut: ClosedRange<CGFloat>

        /// How square the strip stands to an eye straight in front of it, from one lying flat to none
        /// edge-on.
        public var light: CGFloat { abs(cos(angle)) }
    }

    /// The sheet cut into `count` strips, from the hinge outwards.
    public func strips(_ count: Int) -> [Strip] {
        let length = width / CGFloat(count)
        var at = (across: CGFloat(0), toward: CGFloat(0))

        return (0 ..< count).map { index in
            let cut = CGFloat(index) / CGFloat(count) ... CGFloat(index + 1) / CGFloat(count)
            let angle = angle(at: (cut.lowerBound + cut.upperBound) / 2)
            let strip = Strip(across: at.across, toward: at.toward, angle: angle, length: length, cut: cut)

            at = (at.across + length * cos(angle), at.toward + length * sin(angle))
            return strip
        }
    }

    /// How far round the sheet has turned at a point along it, the hinge being nought and the free edge one.
    public func angle(at along: CGFloat) -> CGFloat {
        let lead = Self.lead * sin(turned * .pi) * pow(along, Self.stiffness)

        return min(turned * .pi + lead, .pi)
    }

    /// One strip as an eye sees it, about the middle of its leading edge.
    ///
    /// The strip's layer is placed at the eye itself; `hinge` is where the middle of the hinge stands from
    /// there, and `distance` how far the eye is from the screen.
    public func transform(of strip: Strip, hinge: CGPoint, distance: CGFloat) -> CATransform3D {
        var viewing = CATransform3DIdentity
        viewing.m34 = -1 / distance

        let turning = CATransform3DMakeRotation(-strip.angle, 0, 1, 0)
        let placing = CATransform3DMakeTranslation(hinge.x + strip.across, hinge.y, strip.toward)

        return [ placing, viewing ].reduce(turning, CATransform3DConcat)
    }

    /// Whether the eye sees the strip's front, the side that faced it before the turn began.
    public func showsFront(of strip: Strip, hinge: CGPoint, distance: CGFloat) -> Bool {
        let middle = (
            across: hinge.x + strip.across + strip.length / 2 * cos(strip.angle),
            toward: strip.toward + strip.length / 2 * sin(strip.angle)
        )

        return -sin(strip.angle) * -middle.across + cos(strip.angle) * (distance - middle.toward) > 0
    }

    /// How much further round the free edge is than the hinge, at its most, which is halfway over.
    private static let lead: CGFloat = .pi / 3.5

    /// How the bend gathers towards the free edge: one spreads it evenly, more keeps it off the hinge.
    private static let stiffness: CGFloat = 1.6
}
