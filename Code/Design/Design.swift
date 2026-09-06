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
enum Design {
    /// Every length in the app sits on a lattice of three points.
    enum Space {
        static let unit: CGFloat = 3

        static let extraSmall = unit
        static let small = unit * 2
        static let medium = unit * 3
        static let large = unit * 4
        static let extraLarge = unit * 6
        static let huge = unit * 8
        static let section = unit * 12
    }

    enum Radius {
        static let small = Space.unit * 2
        static let medium = Space.unit * 4
        static let large = Space.unit * 6

        /// A cover rounds in proportion to its own width, so it reads the same at any size.
        static func cover(width: CGFloat) -> CGFloat { width * 0.08 }
    }

    enum Stroke {
        /// A hairline is a device pixel rather than a measurement, which is why it is off the lattice.
        static let hairline: CGFloat = 0.5
        static let ring = Space.unit
    }

    enum Size {
        static let markSmall = Space.unit * 6
        static let mark = Space.unit * 10
        static let control = Space.unit * 12
        /// The smallest thing a finger should have to find.
        static let touch = Space.unit * 15
        static let avatar = Space.unit * 18
        static let rowCover = Space.unit * 22
        static let cover = Space.unit * 24
        static let coverLarge = Space.unit * 40

        /// A glyph inside a circular mark, sized to the mark rather than to a text style.
        static func glyph(in mark: CGFloat) -> CGFloat { mark * 0.45 }

        /// A figure inside a circular mark, which has to fit there rather than be read at a glance.
        static func figure(in mark: CGFloat) -> CGFloat { mark * 0.24 }
    }

    /// The five colours that mean something. Nothing outside this list carries a fact.
    enum Palette {
        /// The reader's own: what they can act on, and how far they have got.
        static let accent = Color.accentColor
        /// Something finished.
        static let positive = Color.green
        /// Something that stands between the reader and the page.
        static let caution = Color.orange
        /// Something wrong.
        static let alert = Color.red
        /// A fact with no colour of its own.
        static let neutral = Color.secondary

        /// The one strength every tinted ground and every edge is drawn at.
        static let veil = 0.15
    }

    enum Surface {
        static let screen = Color(.systemGroupedBackground)
        static let card = Color(.secondarySystemGroupedBackground)
        /// An inert shape: an unselected chip, a tag, a cover with no artwork yet.
        static let fill = Color(.secondarySystemFill)

        static let edge = Color.primary.opacity(Palette.veil)

        /// A badge is filled with its own colour, whichever colour that is.
        static func ground(_ tint: Color) -> Color { tint.opacity(Palette.veil) }
    }

    /// Nine roles, each one system text style, so the whole app follows Dynamic Type.
    enum Style {
        static let screenTitle = Font.largeTitle.bold()
        static let title = Font.title3.bold()
        static let heading = Font.headline
        static let body = Font.body
        /// A row in a list of things: a chapter, a setting.
        static let item = Font.callout
        static let label = Font.subheadline
        static let labelStrong = Font.subheadline.weight(.semibold)
        static let caption = Font.caption
        static let micro = Font.caption2
    }

    /// A cast shadow, at one of two depths.
    struct Shade {
        let color: Color
        let radius: CGFloat
        var x: CGFloat = 0
        var y: CGFloat = 0

        /// Lifts a card off whatever it covers.
        static let card = Shade(color: .black.opacity(Palette.veil), radius: Space.unit * 4, y: Space.unit)
        /// Deeper, for a panel painted the same colour as the page beneath it.
        static let panel = Shade(color: .black.opacity(0.3), radius: Space.unit * 6, y: Space.unit * 2)
        /// The inside edge of a page being turned, cast leftward.
        static let turningPage = Shade(color: .black.opacity(0.3), radius: Space.unit * 5, x: -Space.unit * 2)
    }
}

extension View {
    func shade(_ shade: Design.Shade) -> some View {
        shadow(color: shade.color, radius: shade.radius, x: shade.x, y: shade.y)
    }
}
