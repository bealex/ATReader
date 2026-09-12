//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// How a bound board takes the light at its very edge, and just inside it.
///
/// A spine and a cover are the same board seen from two sides, so both are shaded from these two
/// figures: an edge drawn darker on one than on the other reads as two different books standing
/// together. Lighter on a light shelf, where an edge as black as the dark shelf's cuts the board out
/// of the page.
public enum Board {
    public static func edge(_ scheme: ColorScheme) -> Color { .black.opacity(scheme == .dark ? 0.85 : 0.3) }

    public static func shade(_ scheme: ColorScheme) -> Color { .black.opacity(scheme == .dark ? 0.38 : 0.12) }

    /// The lit lip of the board just past the groove, where a cover is raised off its binding.
    public static func lip(_ scheme: ColorScheme) -> Color { .white.opacity(scheme == .dark ? 0.22 : 0.45) }

    /// The crease a cover is bound along, from its very edge inwards: the groove between it and the
    /// spine, the lip past that catching the light, and the fade onto the artwork.
    ///
    /// Counted in points rather than in fractions of a width, because a binding is a real size: taken
    /// as a share of the cover it is a hair on a small one and a stripe on a large one.
    public static func crease(_ scheme: ColorScheme) -> [(colour: Color, at: CGFloat)] {
        [
            (edge(scheme), 0),
            (edge(scheme), 0.75),
            (shade(scheme), 1.5),
            (lip(scheme), 2.5),
            (lip(scheme).opacity(0), 7),
        ]
    }

    /// The foot of a board, in the shadow of the shelf it stands on: darkest at the bottom edge and
    /// fading upwards, in points from that edge.
    public static func foot(_ scheme: ColorScheme) -> [(colour: Color, at: CGFloat)] {
        let depth = scheme == .dark ? 0.75 : 0.55

        return [
            (.black.opacity(depth), 0),
            (.black.opacity(depth * 0.4), Design.Space.medium),
            (.black.opacity(0), Design.Space.extraLarge),
        ]
    }
}

/// The few points of a cover nearest the hinge, where the board bends into its binding.
///
/// A cover drawn flat to its very edge reads as a card. What says it is bound along that edge is the
/// same darkening a spine carries at each of its own.
public struct CoverHinge: View {
    public init() {}

    @Environment(\.colorScheme)
    private var scheme

    public var body: some View {
        LinearGradient(
            stops: [
                .init(color: Board.edge(scheme), location: 0),
                .init(color: Board.shade(scheme), location: 0.01),
                .init(color: .clear, location: 0.09),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .accessibilityHidden(true)
    }
}
