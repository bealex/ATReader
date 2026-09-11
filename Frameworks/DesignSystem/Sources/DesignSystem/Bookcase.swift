//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// How a bookcase is painted: dark inside, where the board above throws its shadow, and planks darker than
/// the screen in light mode and on the card's colour in dark.
///
/// The figures are the bookcase's own. What they are laid behind is somebody else's artwork, and the dark
/// is what makes a row of covers read as standing inside something rather than on a card.
public enum Bookcase {
    /// The inside of a row from the underside of the board above it down to the plank, as stops.
    ///
    /// Darkest right under the board, where it throws its shadow, lifting through the middle and
    /// darkening again at the floor, where the books meet the plank.
    public static func inside(_ scheme: ColorScheme) -> [(colour: Color, at: CGFloat)] {
        scheme == .dark
            ? [ (grey(0x0A0A0C), 0), (grey(0x19191C), 0.35), (grey(0x1F1F23), 0.88), (grey(0x101012), 1) ]
            : [ (grey(0x46464C), 0), (grey(0x64646B), 0.35), (grey(0x6D6D74), 0.88), (grey(0x55555B), 1) ]
    }

    /// The front of a plank. Light mode's card is lighter than its screen, and planks that colour were the
    /// brightest thing on it; dark mode's card is the right colour already.
    public static func plank(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Design.Surface.card : grey(0xA4A4AB)
    }

    /// How much lighter a plank's top edge is than its front, and how much darker its foot.
    public static let plankLift = 0.22
    public static let plankFall = 0.1

    /// The line of light along a plank's top edge, where the room's light catches it.
    public static func plankHighlight(_ scheme: ColorScheme) -> Color {
        .white.opacity(scheme == .dark ? 0.14 : 0.7)
    }

    /// How dark a series' name and its bracket stand on light mode's plank, as opacities of black. A dark
    /// plank takes the system's secondary and tertiary labels, which read well on it already.
    public static let lightPlankInk = 0.72
    public static let lightPlankRule = 0.45

    /// The line of shadow along a plank's foot, over the row below.
    public static let plankShadow = Color.black.opacity(0.45)

    private static func grey(_ hex: Int) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
