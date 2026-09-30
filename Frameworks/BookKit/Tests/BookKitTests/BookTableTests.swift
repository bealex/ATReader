//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import Testing

@testable import BookKit

/// A table in a chapter body comes out as one block of its own. The tables here are generated nonsense.
struct BookTableTests {
    private static let html = """
        <p>Alpha before.</p>
        <table>
          <thead><tr><th>Bravo</th><th style="text-align:right">Charlie</th></tr></thead>
          <tbody>
            <tr><td>Delta <strong>echo</strong></td><td style="text-align:right">1</td></tr>
            <tr><td><p>Foxtrot</p><p>golf</p></td></tr>
          </tbody>
        </table>
        <p>Hotel after.</p>
        """

    @Test
    func readsATableAsABlockBetweenParagraphs() throws {
        let read = BookHTML.chapter(from: Self.html)

        #expect(read.paragraphs.count == 3)
        #expect(read.paragraphs[0].text == "Alpha before.")
        #expect(read.paragraphs[2].text == "Hotel after.")

        let block = read.paragraphs[1]
        let table = try #require(block.table)

        #expect(block.text.isEmpty)
        #expect(block.isImage)
        #expect(!block.isSceneBreak)
        #expect(table.rows.count == 3)
        #expect(table.headerRows == 1)
        #expect(table.columnCount == 2)
        #expect(table.rows[0].map(\.text) == [ "Bravo", "Charlie" ])
        #expect(table.alignment(ofColumn: 0) == .leading)
        #expect(table.alignment(ofColumn: 1) == .trailing)
    }

    @Test
    func keepsWhatACellSetsApart() throws {
        let table = try #require(BookHTML.chapter(from: Self.html).paragraphs[1].table)
        let cell = table.rows[1][0]

        #expect(cell.text == "Delta echo")
        #expect(cell.styles == [ StyleMark(location: 6, length: 4, emphasis: .bold) ])
    }

    /// Paragraphs inside a cell stay apart, on lines of their own.
    @Test
    func keepsACellsParagraphsApart() throws {
        let table = try #require(BookHTML.chapter(from: Self.html).paragraphs[1].table)

        #expect(table.rows[2].count == 1)
        #expect(table.rows[2][0].text == "Foxtrot\(BookHTML.lineSeparator)golf")
    }

    /// A row of nothing but heading cells heads the table with no `<thead>` round it.
    @Test
    func readsAHeadingRowWithoutAHead() throws {
        let html = "<table><tr><th>India</th></tr><tr><td>Juliet</td></tr></table>"
        let table = try #require(BookHTML.chapter(from: html).paragraphs.first?.table)

        #expect(table.headerRows == 1)
        #expect(table.isHeader(row: 0))
        #expect(!table.isHeader(row: 1))
    }

    /// A chapter stored with a table reads back with it.
    @Test
    func survivesBeingStored() throws {
        let paragraphs = BookHTML.chapter(from: Self.html).paragraphs
        let decoded = try JSONDecoder().decode([ Paragraph ].self, from: JSONEncoder().encode(paragraphs))

        #expect(decoded == paragraphs)
    }
}
