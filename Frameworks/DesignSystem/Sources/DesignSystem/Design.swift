//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// The vocabulary every screen outside the reader is built from.
///
/// Two rules hold it together: every length is a multiple of three, and every colour that carries a
/// fact is one of five. The reader page is deliberately outside both, because its type, its margins
/// and its five tints belong to whoever is reading rather than to this app.
public enum Design {
    /// Every length in the app sits on a lattice of three points.
    public enum Space {
        public static let unit: CGFloat = 3

        public static let extraSmall = unit
        public static let small = unit * 2
        public static let medium = unit * 3
        public static let large = unit * 4
        public static let extraLarge = unit * 6
        public static let huge = unit * 8
        public static let section = unit * 12
    }

    public enum Radius {
        public static let small = Space.unit * 2
        public static let medium = Space.unit * 4
        public static let large = Space.unit * 6
        public static let extraLarge = Space.unit * 9

        /// A cover rounds in proportion to its own width, so it reads the same at any size.
        public static func cover(width: CGFloat) -> CGFloat { width * 0.08 }
    }

    public enum Stroke {
        /// A hairline is a device pixel rather than a measurement, which is why it is off the lattice.
        public static let hairline: CGFloat = 0.5
        public static let ring = Space.unit
    }

    public enum Size {
        /// Every circular mark on a cover. Small on purpose: a mark is a footnote beside the
        /// artwork rather than a second subject.
        public static let mark = Space.unit * 6
        public static let control = Space.unit * 12
        /// The smallest thing a finger should have to find.
        public static let touch = Space.unit * 15
        public static let avatar = Space.unit * 18
        public static let rowCover = Space.unit * 22
        public static let cover = Space.unit * 24
        public static let coverLarge = Space.unit * 40

        /// A glyph inside a circular mark, sized to the mark rather than to a text style.
        public static func glyph(in mark: CGFloat) -> CGFloat { mark * 0.45 }
    }

    /// The five colours that mean something. Nothing outside this list carries a fact.
    public enum Palette {
        /// The reader's own: what they can act on, and how far they have got.
        public static let accent = Color.accentColor
        /// Something finished.
        public static let positive = Color.green
        /// Something that stands between the reader and the page.
        public static let caution = Color.orange
        /// Something wrong.
        public static let alert = Color.red
        /// A fact with no colour of its own.
        public static let neutral = Color.secondary

        /// The one strength every tinted ground and every edge is drawn at.
        public static let veil = 0.15
    }

    public enum Surface {
        public static let screen = Color(.systemGroupedBackground)
        public static let card = Color(.secondarySystemGroupedBackground)
        /// An inert shape: an unselected chip, a tag, a cover with no artwork yet.
        public static let fill = Color(.secondarySystemFill)

        public static let edge = Color.primary.opacity(Palette.veil)

        /// A badge is filled with its own colour, whichever colour that is.
        public static func ground(_ tint: Color) -> Color { tint.opacity(Palette.veil) }
    }

    /// Seven roles, each one system text style, so the whole app follows Dynamic Type.
    public enum Style {
        public static let screenTitle = Font.largeTitle.bold()
        public static let title = Font.title3.bold()
        public static let heading = Font.headline
        /// A row in a list of things: a chapter, a setting. Close enough to body that body never
        /// needed a name: an unstyled Text is already that.
        public static let item = Font.callout
        public static let label = Font.subheadline
        public static let caption = Font.caption
        public static let micro = Font.caption2
    }

    /// What a control is set in.
    ///
    /// Neither of these is one of the text roles, and that is the point: a button is not a sentence.
    /// A heading is a shade small for the thing a screen is for, and a glyph is already a solid shape
    /// that needs none of a heading's weight. Both are written as sizes rather than point counts, so
    /// they still follow Dynamic Type.
    public enum Control {
        /// A full-width action, prominent or not.
        public static let action = Font.system(size: 18, weight: .medium)
        /// An icon-only button in a bar.
        public static let bar = Font.system(size: 20, weight: .regular)
    }

    /// A cast shadow, at one of two depths.
    public struct Shade: Sendable {
        public let color: Color
        public let radius: CGFloat
        public var x: CGFloat = 0
        public var y: CGFloat = 0

        public init(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) {
            self.color = color
            self.radius = radius
            self.x = x
            self.y = y
        }

        /// Lifts a card off whatever it covers.
        public static let card = Shade(color: .black.opacity(Palette.veil), radius: Space.unit * 4, y: Space.unit)
        /// Deeper, for a panel painted the same colour as the page beneath it.
        public static let panel = Shade(color: .black.opacity(0.3), radius: Space.unit * 6, y: Space.unit * 2)
        /// The inside edge of a page being turned, cast leftward.
        public static let turningPage = Shade(color: .black.opacity(0.3), radius: Space.unit * 5, x: -Space.unit * 2)
    }
}

extension View {
    /// The shape of a full-width action: it fills the width and stands at least one control tall.
    ///
    /// Goes on the button's label rather than the button, which is what makes the label fill. Pair it
    /// with `.controlSize(.small)` on the button itself, so the minimum height below is what
    /// governs and two actions on one screen agree whether one of them is prominent or not.
    public func actionLabel() -> some View {
        font(Design.Control.action)
            .frame(maxWidth: .infinity, minHeight: Design.Size.control)
    }

    /// An icon-only button in a navigation bar: the title's size at its plain weight, over a hit area
    /// a finger can find.
    ///
    /// A glyph is already a solid shape. Setting one at the title's own bold makes it read as heavier
    /// than the words beside it rather than as the same size.
    public func barGlyph() -> some View {
        font(Design.Control.bar)
            .frame(width: Design.Size.control, height: Design.Size.control)
    }

    public func shade(_ shade: Design.Shade) -> some View {
        shadow(color: shade.color, radius: shade.radius, x: shade.x, y: shade.y)
    }
}
