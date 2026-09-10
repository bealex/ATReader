//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import QuartzCore

/// Two panels hinged along one edge, turning together about the outer edge of the first, at one moment
/// of that turn.
///
/// What a book does when it is taken down off a shelf: the edge it stood on swings away, and the face
/// folded in behind it comes round. Both ends of the turn lie in the screen's own plane, so neither panel
/// is ever drawn larger than it is laid out.
///
/// A value rather than a view, because a shelf has to lay out the books beside a fold before anything is
/// drawn, and whatever draws it works every frame out from the turn itself: halfway between two
/// projections is not the projection of half a turn.
public struct Hinge {
    public let edge: CGFloat
    public let face: CGFloat
    /// How far round the pair has turned: none of it stands the edge to the reader, all of it the face.
    public let turned: CGFloat

    public init(edge: CGFloat, face: CGFloat, turned: CGFloat) {
        self.edge = edge
        self.face = face
        self.turned = turned
    }

    public enum Panel {
        case edge
        case face
    }

    /// What the pair covers straight across.
    public var width: CGFloat {
        edge * cos(angle) + face * sin(angle) * depth / (depth + face * cos(angle))
    }

    /// Never quite flat to the eye: a panel exactly edge-on projects onto a line, and a transform that
    /// flattens what it is given is dropped rather than drawn.
    private var least: CGFloat { Self.sliver / max(edge, face) }

    private var angle: CGFloat { least + min(max(turned, 0), 1) * (.pi / 2 - 2 * least) }

    private var depth: CGFloat { face * Self.perspective }

    /// How square a panel stands to the light, which is full on the one facing the reader.
    public func light(of panel: Panel) -> CGFloat { panel == .face ? sin(angle) : cos(angle) }

    /// One panel, as an eye sees it, about the panel's own top left.
    ///
    /// The eye stands `eye` down the panel's own space and in front of the hinge, so a panel turning
    /// away from it leaves the screen edge-on rather than showing its back. The two panels are placed in
    /// one space and projected one at a time rather than nested, because a rotation inside a rotation is
    /// flattened between the two and the joint comes apart.
    public func transform(of panel: Panel, eye: CGFloat) -> CATransform3D {
        let (across, into) = (cos(angle), sin(angle))
        let isFace = panel == .face
        // Where the panel's leading edge stands and where its own width runs from there. The hinge is
        // held in the screen's own plane, so both ends of the turn come out flat.
        // The edge reaches a little past the hinge, under the face, rather than the two meeting along a
        // line: a line is where two rasterisers each round the same pixel their own way and leave a
        // hair of nothing between them.
        //
        // Held to the same hair on the screen however far the pair has turned, which is why it is
        // divided by how square the edge stands: a length laid along a board nearly edge-on to the
        // reader covers almost nothing, and near the spine is where the joint is widest open.
        let overrun = Self.seam / max(across, Self.leastFacing)
        let reach = edge > 0 ? (edge + overrun) / edge : 1
        let start = isFace ? (x: edge * across, z: 0) : (x: 0, z: -edge * into)
        let along = isFace ? (x: into, z: -across) : (x: across * reach, z: into * reach)

        var placed = CATransform3DIdentity
        placed.m11 = along.x
        placed.m13 = along.z
        placed.m41 = start.x
        placed.m43 = start.z

        var viewing = CATransform3DIdentity
        viewing.m34 = -1 / depth

        let toEye = CATransform3DMakeTranslation(-edge * across, -eye, 0)
        let fromEye = CATransform3DMakeTranslation(edge * across, eye, 0)

        return [ toEye, viewing, fromEye ].reduce(placed, CATransform3DConcat)
    }

    /// How far off the eye stands, in the face's own widths. Nearer exaggerates the turn.
    private static let perspective: CGFloat = 3

    /// The most a panel may be left standing where it is meant to be edge-on.
    private static let sliver: CGFloat = 0.05

    /// How far past the hinge the edge reaches, on the screen rather than on the board.
    private static let seam: CGFloat = 0.5

    /// How square a panel is taken to stand for that reckoning, however much further it has turned. A
    /// panel past this is too nearly edge-on to be drawn at all, and its overrun would run away.
    private static let leastFacing: CGFloat = 0.2

    /// How much of its colour a panel gives up as it turns out of the light.
    public static let shading: CGFloat = 0.55

    /// How square to the reader a panel stands before a touch on the pair is meant for it, which is
    /// halfway round the turn.
    public static let facing = cos(CGFloat.pi / 4)
}
