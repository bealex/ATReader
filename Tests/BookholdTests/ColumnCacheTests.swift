//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookRenderer
import Foundation
import SwiftUI
import Testing

@testable import Bookhold

/// Breaking a chapter into lines is the expensive half of opening a book, so the lines are kept and
/// read back. A column read back has to be the column that was composed, to the point: a difference of
/// a quarter of a point in one line's height moves every page break under it, and the text would be set
/// one way on the first open and another way on the second.
@MainActor
struct ColumnCacheTests {
    /// Remembers what it was given, and counts what was asked of it.
    private actor Columns: ColumnStore {
        private(set) var kept: [String: Data] = [:]
        private(set) var reads = 0

        func column(chapterId: Int, fingerprint: String) async -> Data? {
            reads += 1
            return kept["\(chapterId)|\(fingerprint)"]
        }

        func store(column: Data, chapterId: Int, fingerprint: String) async {
            kept["\(chapterId)|\(fingerprint)"] = column
        }

        /// Cuts every kept column down to its first `count` lines, which is how a restored layout is
        /// told apart from a freshly composed one.
        func shorten(to count: Int) throws {
            for (key, packed) in kept {
                let unpacked = try (packed as NSData).decompressed(using: .zlib) as Data
                var column = try JSONSerialization.jsonObject(with: unpacked) as! [String: Any]
                column["lines"] = Array((column["lines"] as! [Any]).prefix(count))
                let written = try JSONSerialization.data(withJSONObject: column)

                kept[key] = try (written as NSData).compressed(using: .zlib) as Data
            }
        }
    }

    private static let context = JustificationTests.testContext

    private static func layout(
        style: ChapterTextStyle? = nil,
        columns: (any ColumnStore)? = nil
    ) async -> ChapterLayout {
        var context = Self.context

        if let style { context.style = style }

        return await ChapterLayout.make(
            chapterId: 7,
            content: await ChapterContent.prepare(html: (1...6).map { _ in
                "<p>\(JustificationTests.words(90))</p>"
            }.joined()),
            heading: ChapterHeading.make(position: 1, title: "Глава первая"),
            context: context,
            columns: columns
        )
    }

    /// A chapter whose words are the same but whose setting is not gets its own column.
    ///
    /// What a re-read of a book changes is most often how it is set rather than what it says: an
    /// epigraph that used to be centred is held off both edges, a phrase gains a face of its own. The
    /// characters are identical, and lines composed for the one are nothing like the lines for the
    /// other.
    private static func layout(html: String, columns: (any ColumnStore)?) async -> ChapterLayout {
        await ChapterLayout.make(
            chapterId: 7,
            content: await ChapterContent.prepare(html: html),
            heading: ChapterHeading(),
            context: Self.context,
            columns: columns
        )
    }

    @Test
    func keepsAColumnAgainstHowTheTextIsSetAndNotOnlyItsWords() async throws {
        let words = JustificationTests.words(90)
        let plain = "<p>\(words)</p>"
        let quoted = #"<p data-inset="1">\#(words)</p>"#
        let columns = Columns()

        _ = await Self.layout(html: plain, columns: columns)

        #expect(await columns.kept.count == 1)

        let held = await Self.layout(html: quoted, columns: columns)

        #expect(await columns.kept.count == 2, "the quoted passage was given the plain one's lines")

        let fresh = await Self.layout(html: quoted, columns: nil)

        #expect(held.typesetLines.map(\.width) == fresh.typesetLines.map(\.width))
        #expect(held.typesetLines.first?.origin ?? 0 > 0, "the quoted passage was not held off the edge")
    }

    /// The same words in a face of their own reach a different width, and so break differently.
    @Test
    func keepsAColumnAgainstTheFacesTheWordsAreSetIn() async throws {
        let words = JustificationTests.words(90)
        let columns = Columns()

        _ = await Self.layout(html: "<p>\(words)</p>", columns: columns)
        _ = await Self.layout(html: "<p><strong>\(words)</strong></p>", columns: columns)

        #expect(await columns.kept.count == 2, "the bold passage was given the plain one's lines")
    }

    /// Two quotations one after another read as two, not as one run of text.
    @Test
    func standsAQuotationsSourceClearOfTheWordsItNames() async throws {
        let quoted = #"<p data-inset="1">\#(JustificationTests.words(20))</p>"#
        let source = #"<p data-source="1" data-inset="1"><em>Некто</em></p>"#
        let layout = await Self.layout(html: quoted + source + quoted + source, columns: nil)
        let lines = layout.typesetLines

        let sources = lines.indices.filter { lines[$0].text.contains("Некто") }

        try #require(sources.count == 2, "the two sources were not set")

        // The air stands above the line, so a source and whatever follows one are taller than the
        // lines of the quotation they part.
        let ordinary = try #require(lines.filter { !$0.text.contains("Некто") }.map(\.height).min())

        for index in sources { #expect(lines[index].height > ordinary, "the source stood in no air") }

        let after = try #require(sources.first.map { $0 + 1 })

        #expect(lines[after].height > ordinary, "what followed the source stood in no air")
    }

    /// Every line of a restored layout stands where the composed one put it.
    @Test
    func aKeptColumnGivesBackTheSameLines() async throws {
        let columns = Columns()
        let fresh = await Self.layout()
        let composed = await Self.layout(columns: columns)
        let restored = await Self.layout(columns: columns)

        #expect(await columns.kept.count == 1, "the composed column was kept")
        #expect(restored.pageRanges == fresh.pageRanges)
        #expect(restored.pageCount == composed.pageCount)

        let was = fresh.typesetLines
        let now = restored.typesetLines

        try #require(now.count == was.count, "a restored chapter breaks into as many lines")

        for (index, line) in now.enumerated() {
            let old = was[index]

            #expect(line.text == old.text, "line \(index)")
            #expect(line.width == old.width, "line \(index) width")
            #expect(line.height == old.height, "line \(index) height")
            #expect(line.baseline == old.baseline, "line \(index) baseline")
            #expect(line.gapMultiple == old.gapMultiple, "line \(index) gap")
            #expect(line.gaps == old.gaps, "line \(index) gap count")
            #expect(line.isJustified == old.isJustified, "line \(index) justification")
            #expect(line.isHeading == old.isHeading, "line \(index) heading")
            #expect(line.startsParagraph == old.startsParagraph, "line \(index) opens a paragraph")
            #expect(line.endsParagraph == old.endsParagraph, "line \(index) ends a paragraph")
        }
    }

    /// The kept column is what the second layout is set from, rather than being composed again and
    /// happening to agree.
    @Test
    func theKeptColumnIsWhatIsSet() async throws {
        let columns = Columns()

        _ = await Self.layout(columns: columns)
        try await columns.shorten(to: 5)

        let restored = await Self.layout(columns: columns)

        #expect(restored.typesetLines.count == 5)
    }

    /// A column is kept against the setting it was broken for, so a change of type composes again
    /// instead of drawing lines broken for a different one.
    @Test
    func aChangeOfTypeThrowsTheColumnAway() async throws {
        let columns = Columns()
        var larger = Self.context.style
        larger.fontSize += 4

        _ = await Self.layout(columns: columns)
        let composed = await Self.layout(style: larger, columns: columns)
        let fresh = await Self.layout(style: larger)

        #expect(await columns.kept.count == 2, "each setting keeps its own column")
        #expect(composed.typesetLines.count == fresh.typesetLines.count)
        #expect(composed.pageRanges == fresh.pageRanges)
    }
}
