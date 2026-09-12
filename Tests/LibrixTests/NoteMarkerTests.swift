//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookRenderer
import Foundation
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

    /// A marker covers its own characters in every setting, however many word joiners and soft
    /// hyphens the typesetter put in before it.
    @Test
    func aMarkerStaysOnItsCharactersThroughEverySetting() async {
        let html = """
            <p>и в а ко бразуметство и в а ко мудрахленье<a href="#n2">[2]</a> а посему, грыштальники</p>
            <p id="n2">Зябровка кутельная.</p>
            """
        let content = await ChapterContent.prepare(html: html)

        for paragraphs in [ content.paragraphs, content.hyphenated ] {
            let paragraph = paragraphs[0]
            let mark = paragraph.notes.first

            #expect(mark.map { (paragraph.text as NSString).substring(with: $0.range) } == "[2]")
        }
    }
}
