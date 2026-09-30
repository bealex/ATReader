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

    /// The face of a leaf `depth` thick that lay against the page, cut as `strips` cut the front: one
    /// strip behind each, meeting its neighbours at the joints.
    public func back(of strips: [Strip], depth: CGFloat) -> [Strip] {
        guard !strips.isEmpty else { return [] }

        let angles = strips.map(\.angle)
        // Each joint is set in along the bisector of the strips either side, far enough to keep the depth.
        let joints = (0 ... strips.count).map { index in
            let before = angles[max(index - 1, 0)]
            let after = angles[min(index, angles.count - 1)]
            let middle = (before + after) / 2
            let reach = depth / max(cos((after - before) / 2), 0.1)
            let front =
                index < strips.count
                ? (strips[index].across, strips[index].toward)
                : (
                    strips[index - 1].across + strips[index - 1].length * cos(before),
                    strips[index - 1].toward + strips[index - 1].length * sin(before)
                )

            return (across: front.0 + reach * sin(middle), toward: front.1 - reach * cos(middle))
        }

        return strips.indices.map { index in
            let start = joints[index]
            let end = joints[index + 1]

            return Strip(
                across: start.across,
                toward: start.toward,
                angle: atan2(end.toward - start.toward, end.across - start.across),
                length: hypot(end.across - start.across, end.toward - start.toward),
                cut: strips[index].cut
            )
        }
    }

    /// The two ends of a leaf `depth` thick cut into `strips`, each as a strip running from its front
    /// face to its back one: at the free edge, and at the hinge.
    public func edges(depth: CGFloat, of strips: [Strip]) -> (fore: Strip, spine: Strip)? {
        guard let first = strips.first, let last = strips.last else { return nil }

        let fore = Strip(
            across: last.across + last.length * cos(last.angle),
            toward: last.toward + last.length * sin(last.angle),
            angle: last.angle - .pi / 2,
            length: depth,
            cut: 1 ... 1
        )
        let spine = Strip(
            across: first.across,
            toward: first.toward,
            angle: first.angle - .pi / 2,
            length: depth,
            cut: 0 ... 0
        )

        return (fore, spine)
    }

    /// How far round the sheet has turned at a point along it, the hinge being nought and the free edge one.
    public func angle(at along: CGFloat) -> CGFloat {
        let lead = Self.lead * sin(turned * .pi) * pow(along, Self.stiffness)

        return min(turned * .pi + lead, .pi)
    }

    /// How square the sheet stands to an eye straight in front of it at a point along it, from one lying
    /// flat to none edge-on.
    public func light(at along: CGFloat) -> CGFloat { abs(cos(angle(at: along))) }

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
