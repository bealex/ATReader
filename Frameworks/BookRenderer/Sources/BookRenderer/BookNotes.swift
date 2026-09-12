//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import CoreText
import UIKit

public extension NSAttributedString.Key {
    /// The note a marker points at, carried by the characters that stand for it.
    static let bookNote = NSAttributedString.Key("ATBookNote")
}

/// A marker a finger found: the note it points at, and the box it stands in on the page.
public struct NoteHit: Sendable {
    public let id: String
    /// Where the marker sits in the page's own coordinates, so an aside can point at it rather than
    /// at the finger that went looking for it.
    public let rect: CGRect

    public init(id: String, rect: CGRect) {
        self.id = id
        self.rect = rect
    }
}

/// How a note's marker is set, and how large a target it makes.
public enum NoteMarker {
    /// How large a marker is set against the body text.
    public static let scale = 0.65

    /// How far above the line a marker stands.
    ///
    /// Short of what a printed superscript takes. The column reads its line height and its baseline
    /// off the body font, so a marker climbing higher than the body's own ascent would foul the line
    /// above it.
    public static let rise = 0.25

    /// What a marker's `.baselineOffset` is set to against a given type size.
    ///
    /// Negative. The page draws through a flipped text matrix, so CoreText's own upwards is the page's
    /// downwards and a positive offset sinks the marker below the line instead of lifting it clear.
    public static func baselineOffset(forFontSize size: Double) -> Double { -size * rise }

    /// How wide a marker is treated as being when a finger goes for it, whatever it measures.
    ///
    /// A superscript digit is two or three points across and no finger finds that. The target is
    /// widened about the marker's own middle, which is what makes one tappable without moving it.
    static let target: CGFloat = 30
}

/// How a formula's lowered and lifted figures are set.
///
/// The same size as a note's marker, since both are figures beside the words rather than words, and
/// the same restraint about how far they go: the column takes its line height from the body font, so
/// one climbing past the body's own ascent would foul the line above it.
public enum ScriptMarker {
    /// How far below the line a lowered figure sits, as a share of the type size. Shorter than the
    /// lift above it, because the line below is closer than the line above.
    public static let drop = 0.14

    /// What a figure's `.baselineOffset` is set to against a given type size.
    ///
    /// The page draws through a flipped text matrix, so CoreText's own upwards is the page's
    /// downwards: lifting a figure takes a negative offset and dropping one takes a positive.
    public static func baselineOffset(_ place: ScriptMark.Place, forFontSize size: Double) -> Double {
        switch place {
            case .below: size * drop
            case .above: -size * NoteMarker.rise
        }
    }
}
