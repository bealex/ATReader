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

        /// The smallest step on the lattice. What a glyph needs to read as level with the type beside
        /// it, and the tightest gap there is, for the one place where the ordinary one crowds out what
        /// it is meant to be separating.
        public static let nudge = unit / 3
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
        /// A book block is square-cut. What rounds a spine is the light falling across it, not its
        /// corners, so this is barely a radius at all: enough to take the point off, and no more.
        public static let spine = Space.unit / 3

        /// A printed cover is cut square along the edge it is bound on, so that corner is the same
        /// barely-there radius a spine takes.
        public static let cover = spine

        /// The outer corners of a cover, away from the binding. A book is rounded where it is handled
        /// and square where it is held together.
        public static let foreEdge = Space.unit * 2
    }

    public enum Stroke {
        /// A hairline is a device pixel rather than a measurement, which is why it is off the lattice.
        public static let hairline: CGFloat = 0.5
        /// The line under a run of books on a shelf, a shade over a hairline so it reads across the plank.
        public static let bracket = hairline * 1.3
        public static let ring = Space.unit
        /// The reading line along the top of a cover, and the line of shade under it.
        public static let readingLine = Space.extraSmall
        public static let readingShade = hairline * 2
    }

    public enum Size {
        /// Every circular mark on a cover. Small on purpose: a mark is a footnote beside the
        /// artwork rather than a second subject.
        public static let mark = Space.unit * 6
        /// A bookmark hanging on a cover: a narrow ribbon, taller than it is wide.
        public static let bookmark = Space.unit * 5
        public static let bookmarkHeight = Space.unit * 7
        public static let control = Space.unit * 12
        /// The smallest thing a finger should have to find.
        public static let touch = Space.unit * 15
        public static let avatar = Space.unit * 18
        /// A cover in a list row, where it is a reminder of which book this is rather than the
        /// subject of the row.
        public static let listCover = Space.unit * 13
        public static let rowCover = Space.unit * 22
        public static let cover = Space.unit * 24
        public static let coverLarge = Space.unit * 40
        /// A cover standing in a series' own shelf, sized so three or four fit across a phone.
        public static let gridCover = Space.unit * 32
        /// The thinnest a book stands on its edge. A spine narrower than this has no room left for
        /// the writing once its own shading is off.
        public static let spine = Space.unit * 6
        /// How far a cover is thrown out of focus behind a spine. Enough that no part of the picture
        /// is legible, since what is wanted is its colour.
        public static let spineBlur = Space.unit * 4
        /// How wide an aside stands beside what it belongs to, and how deep before it scrolls.
        ///
        /// Narrow on purpose. An aside nearly as wide as the screen has nowhere to go, so it is
        /// clamped to the middle and points at whatever happens to be under it.
        public static let callout = Space.unit * 104
        /// What is left for an aside's own content once its padding is off.
        public static let calloutText = callout - Space.extraLarge * 2
        public static let calloutDepth = Space.unit * 64

        /// A glyph inside a circular mark, sized to the mark rather than to a text style.
        public static func glyph(in mark: CGFloat) -> CGFloat { mark * 0.45 }

        /// How wide a cover stands so that a row of them fills the space it is given exactly.
        ///
        /// Covers are laid out at one size across the whole shelf, and a fixed size leaves a ragged
        /// margin down the right that changes with the width of the screen. So the size wanted decides
        /// how many go in a row, the count is rounded to a whole number of them, and what is actually
        /// there is shared out between that many.
        public static func coverWidth(across available: CGFloat, ideal: CGFloat = gridCover, spacing: CGFloat)
            -> CGFloat
        {
            guard available > 0 else { return ideal }

            let count = max(1, (available / ideal).rounded())

            return (available - spacing * (count - 1)) / count
        }

        /// How tall a slot a cover of this width needs. Half again as tall as it is wide unless the
        /// books themselves say otherwise: a shelf measures its own tallest and gives that to all.
        public static func coverHeight(width: CGFloat, ratio: CGFloat = 1.5) -> CGFloat {
            // Whole points. A shelf works its heights out from the shape of each cover, and a book
            // standing a third of a point above its neighbour draws a soft edge along the top of it.
            (width * max(ratio, 1)).rounded()
        }
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
        // The three the system names, which it names differently on each platform. The package builds
        // for the Mac so its own logic can be tested there; nothing of the app is drawn on one.
        #if canImport(UIKit)
            /// Slate grey in light mode rather than the system's near-white, which left the covers standing
            /// on white; the system's own in dark mode.
            public static let screen = Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor.systemGroupedBackground.resolvedColor(with: traits)
                    : UIColor(red: 0xCB / 255, green: 0xCB / 255, blue: 0xD1 / 255, alpha: 1)
            })
            public static let card = Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits)
                    : UIColor(red: 0xDD / 255, green: 0xDD / 255, blue: 0xE3 / 255, alpha: 1)
            })
            /// An inert shape: an unselected chip, a tag, a cover with no artwork yet.
            public static let fill = Color(.secondarySystemFill)
        #else
            public static let screen = Color(nsColor: .windowBackgroundColor)
            public static let card = Color(nsColor: .controlBackgroundColor)
            /// An inert shape: an unselected chip, a tag, a cover with no artwork yet.
            public static let fill = Color(nsColor: .quaternarySystemFill)
        #endif

        public static let edge = Color.primary.opacity(Palette.veil)

        /// The paint under words a reader has picked out, in whatever colour the words are set in.
        public static func picked(_ foreground: Color) -> Color {
            foreground.opacity(Palette.veil * 1.5)
        }

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
        /// What is printed on a book's spine: a point under the smallest role and as narrow as the
        /// face goes, because the width of a spine belongs to the book and the writing lives in what
        /// is left of it. Narrow beats rounded where a face offers only one of the two.
        public static let spine = Font.system(size: spineSize, weight: .medium).width(.compressed)

        /// The same figure again, for the spine that is printed into a picture rather than laid out.
        public static let spineSize: CGFloat = 9
    }

    /// What a control is set in.
    ///
    /// Neither of these is one of the text roles, and that is the point: a button is not a sentence.
    /// A heading is a shade small for the thing a screen is for, and a glyph is already a solid shape
    /// that needs none of a heading's weight. Both are written as sizes rather than point counts, so
    /// they still follow Dynamic Type.
    public enum Control {
        /// A full-width action, prominent or not.
        public static let action = Font.system(size: actionSize, weight: .medium)
        /// An icon-only button in a bar.
        public static let barGlyph = Font.system(size: barGlyphSize, weight: .regular)

        /// The same two figures, for the glyphs a shelf draws rather than lays out.
        public static let actionSize: CGFloat = 18
        public static let barGlyphSize: CGFloat = 20
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
        font(Design.Control.barGlyph)
            .frame(width: Design.Size.control, height: Design.Size.control)
    }

    public func shade(_ shade: Design.Shade) -> some View {
        shadow(color: shade.color, radius: shade.radius, x: shade.x, y: shade.y)
    }
}

extension View {
    /// A list set on the app's own screen colour rather than the system's, which is white in light mode.
    public func listOnScreen() -> some View {
        scrollContentBackground(.hidden).background(Design.Surface.screen)
    }
}
