//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookRenderer
import Foundation
import Testing
import UIKit

/// How a note's marker is set against the body it stands in.
struct NoteMarkerTests {
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

    // MARK: - Where the ink lands

    /// Drawn, a marker's ink stands clear above the line's baseline. The sign of the offset says
    /// nothing on its own: how a run is drawn decides which way CoreText takes it.
    @Test
    func aMarkerIsDrawnAboveTheLine() async throws {
        let ink = try await Self.ink(of: ##"<p>шшшш <a href="#n1">4</a></p><p id="n1">Зябровка.</p>"##)

        #expect(ink.mark.bottom < ink.words.bottom - 2, "the marker sank to the foot of the line")
    }

    @Test
    func aLiftedFigureIsDrawnAboveTheLineAndALoweredOneBelowIt() async throws {
        let lifted = try await Self.ink(of: "<p>шшшш <sup>4</sup></p>")
        let lowered = try await Self.ink(of: "<p>шшшш <sub>4</sub></p>")

        #expect(lifted.mark.bottom < lifted.words.bottom - 2, "a lifted figure sank")
        #expect(lowered.mark.bottom > lowered.words.bottom, "a lowered figure rose")
    }

    /// Where the ink of a one-line paragraph stands, in rows: the words before the gap, and the figure
    /// after it.
    @MainActor
    private static func ink(of html: String) async throws -> (words: Rows, mark: Rows) {
        let context = JustificationTests.testContext
        let layout = await ChapterLayout.make(
            chapterId: 1,
            content: await ChapterContent.prepare(html: html),
            heading: ChapterHeading(),
            context: context
        )
        let format = UIGraphicsImageRendererFormat()

        format.scale = 2
        format.preferredRange = .standard

        let image = UIGraphicsImageRenderer(size: context.pageSize, format: format).image { drawing in
            UIColor.white.setFill()
            drawing.fill(CGRect(origin: .zero, size: context.pageSize))
            layout.draw(layout.pages[0], palette: nil)
        }
        let picture = try #require(image.cgImage)
        let data = try #require(picture.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        let width = picture.width
        let stride = picture.bytesPerRow
        let isInk = { (x: Int, y: Int) in bytes[y * stride + x * 4] < 128 }
        let columns = (0 ..< width).filter { x in (0 ..< picture.height).contains { isInk(x, $0) } }
        let gap = try #require(zip(columns, columns.dropFirst()).max { ($0.1 - $0.0) < ($1.1 - $1.0) })

        func rows(_ range: ClosedRange<Int>) -> Rows {
            let inked = (0 ..< picture.height).filter { y in range.contains { isInk($0, y) } }

            return Rows(top: inked.first ?? 0, bottom: inked.last ?? 0)
        }

        return (rows(columns[0] ... gap.0), rows(gap.1 ... columns[columns.count - 1]))
    }

    private struct Rows {
        let top: Int
        let bottom: Int
    }
}
