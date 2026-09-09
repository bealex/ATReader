//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookRenderer
import Testing

/// How a note's marker is set against the body it stands in.
struct NoteMarkerTests {
    /// A marker stands above the line, and the sign of that is not the obvious one.
    ///
    /// The page draws through a flipped text matrix, so CoreText's own upwards is the page's
    /// downwards. Asking for a positive rise sank every marker below its line, which is what this
    /// keeps from coming back.
    @Test
    func aMarkerIsRaisedRatherThanSunk() {
        #expect(NoteMarker.baselineOffset(forFontSize: 19) < 0)
    }

    /// A marker is smaller than the body but not so small it stops being readable.
    @Test
    func aMarkerIsSetSmallerThanTheBody() {
        #expect(NoteMarker.scale > 0.5)
        #expect(NoteMarker.scale < 1)
    }

    /// The rise is short of a printed superscript's: the column takes its line height and its baseline
    /// from the body font, so a marker climbing past the body's ascent would foul the line above.
    @Test
    func aMarkerStaysInsideTheLineItStandsOn() {
        let size = 19.0
        let top = abs(NoteMarker.baselineOffset(forFontSize: size)) + size * NoteMarker.scale * 0.75

        #expect(top < size * 0.8)
    }
}
