//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Foundation
import Testing

@testable import BookFormats

/// Reading a book out of a Markdown file. Every document here is written for the test.
struct MarkdownFormatTests {
    private func book(_ text: String) throws -> ParsedBook {
        try MarkdownFormat.parse(Data(text.utf8))
    }

    private func html(_ text: String) throws -> String {
        try #require(book(text).sections.first).html
    }

    // MARK: - Telling it apart

    @Test
    func readsTextAndTurnsDownMarkupAndArchives() {
        let format = MarkdownFormat()

        #expect(format.canRead(Data("# Alpha\n\nBravo.".utf8)))
        #expect(format.canRead(Data("Plain words.".utf8)))
        #expect(!format.canRead(Data("<?xml version=\"1.0\"?><FictionBook/>".utf8)))
        #expect(!format.canRead(Data([ 0x50, 0x4B, 0x03, 0x04, 0, 0 ])))
        #expect(!format.canRead(Data([ 0xC3, 0x28, 0xA0, 0xA1 ])))
    }

    // MARK: - Chapters

    /// A lone heading opening the document names the book, and the level below it cuts the chapters.
    @Test
    func namesTheBookAfterALoneOpeningHeading() throws {
        let read = try book("# Alpha\n\n## Bravo\n\nCharlie.\n\n## Delta\n\nEcho.\n")

        #expect(read.title == "Alpha")
        #expect(read.format == "md")
        #expect(read.sections.map(\.title) == [ "Bravo", "Delta" ])
        #expect(read.sections.map(\.level) == [ 1, 1 ])
        #expect(read.sections[0].html == "<h1 data-anchor=\"bravo\">Bravo</h1><p>Charlie.</p>")
    }

    /// What stands between the book's name and its first chapter is a page of its own, under that name.
    @Test
    func keepsAnOpeningUnderTheBooksName() throws {
        let read = try book("# Alpha\n\nForeword.\n\n## Bravo\n\nCharlie.\n")

        #expect(read.sections.map(\.title) == [ "Alpha", "Bravo" ])
        #expect(read.sections[0].html.contains("<p>Foreword.</p>"))
    }

    /// Two levels go into the contents, and anything deeper stays a heading inside its section.
    @Test
    func cutsChaptersAndSectionsAndLeavesDeeperHeadingsInPlace() throws {
        let read = try book(
            """
            # Alpha

            Bravo.

            ## Charlie

            Delta.

            ### Echo

            Foxtrot.

            # Golf

            Hotel.
            """
        )

        #expect(read.sections.map(\.title) == [ "Alpha", "Charlie", "Golf" ])
        #expect(read.sections.map(\.level) == [ 1, 2, 1 ])
        #expect(read.sections[1].html.contains("<h2 data-anchor=\"charlie\">Charlie</h2>"))
        #expect(read.sections[1].html.contains("<h3 data-anchor=\"echo\">Echo</h3>"))
    }

    @Test
    func takesTheFrontMatter() throws {
        let read = try book(
            """
            ---
            title: "India Juliet"
            author: Kilo Lima, Mike November
            lang: en
            ---

            Oscar papa.
            """
        )

        #expect(read.title == "India Juliet")
        #expect(read.authors == [ "Kilo Lima", "Mike November" ])
        #expect(read.language == "en")
        #expect(read.sections.count == 1)
        #expect(read.sections[0].html == "<p>Oscar papa.</p>")
    }

    @Test
    func readsUnderlinedHeadings() throws {
        let read = try book("Alpha\n=====\n\nBravo\n-----\n\nCharlie.\n\nDelta\n-----\n\nEcho.\n")

        #expect(read.title == "Alpha")
        #expect(read.sections.map(\.title) == [ "Bravo", "Delta" ])
    }

    // MARK: - Inside a paragraph

    @Test
    func keepsEmphasis() throws {
        #expect(
            try html("Alpha **bravo** *charlie* ***delta*** __echo__ _foxtrot_.")
                == "<p>Alpha <strong>bravo</strong> <em>charlie</em> <em><strong>delta</strong></em> "
                + "<strong>echo</strong> <em>foxtrot</em>.</p>"
        )
    }

    @Test
    func leavesMarksThatCloseNothing() throws {
        #expect(try html("Two * three and snake_case_name.") == "<p>Two * three and snake_case_name.</p>")
        #expect(try html("An \\*escaped\\* star.") == "<p>An *escaped* star.</p>")
    }

    @Test
    func setsCodeAsWrittenAndEscapesMarkup() throws {
        #expect(try html("Run `a < b && *c*` now.") == "<p>Run a &lt; b &amp;&amp; *c* now.</p>")
    }

    @Test
    func joinsLinesAndBreaksWhereAsked() throws {
        #expect(try html("Alpha\nbravo  \ncharlie") == "<p>Alpha bravo<br>charlie</p>")
    }

    /// A link off the page keeps its words; one to a heading in the book goes on pointing at it.
    @Test
    func keepsALinksWordsAndFollowsOneIntoTheBook() throws {
        let read = try book(
            "# Alpha\n\n## Bravo\n\nSee [the site](https://example.com) and [below](#charlie).\n\n## Charlie\n\nDelta.\n"
        )

        #expect(read.sections[0].html.contains("See the site and <a href=\"#charlie\">below</a>."))
    }

    @Test
    func writesAFootnoteUnderTheChapterThatPointsAtIt() throws {
        let read = try book("# Alpha\n\n## Bravo\n\nCharlie[^1].\n\n## Delta\n\nEcho.\n\n[^1]: Foxtrot *golf*.\n")

        #expect(
            read.sections[0].html
                == "<h1 data-anchor=\"bravo\">Bravo</h1><p>Charlie<a href=\"#fn-1\">1</a>.</p>"
                + "<p id=\"fn-1\">Foxtrot <em>golf</em>.</p>"
        )
        #expect(!read.sections[1].html.contains("fn-1"))
    }

    @Test
    func keepsAPictureTheDocumentCarries() throws {
        let pixel = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
        let read = try book("Alpha.\n\n![Bravo](data:image/png;base64,\(pixel))\n\n![Charlie](elsewhere.png)\n")

        #expect(read.images.keys.sorted() == [ "picture-1.png" ])
        #expect(read.sections[0].html.contains("<img src=\"picture-1.png\">"))
        #expect(!read.sections[0].html.contains("elsewhere"))
    }

    // MARK: - Blocks

    @Test
    func marksListsAndHowDeepTheyStand() throws {
        let text = """
            - Alpha
            - Bravo
              continued
              1. Charlie
              2. Delta
            - [x] Echo
            """

        #expect(
            try html(text)
                == [
                    "<p data-list=\"1\">• Alpha</p>",
                    "<p data-list=\"1\">• Bravo continued</p>",
                    "<p data-list=\"2\">1. Charlie</p>",
                    "<p data-list=\"2\">2. Delta</p>",
                    "<p data-list=\"1\">☑ Echo</p>",
                ].joined()
        )
    }

    @Test
    func numbersAListThatRepeatsItsFirstNumber() throws {
        #expect(
            try html("1. Alpha\n1. Bravo\n1. Charlie")
                == "<p data-list=\"1\">1. Alpha</p><p data-list=\"1\">2. Bravo</p><p data-list=\"1\">3. Charlie</p>"
        )
    }

    @Test
    func holdsAQuotationOffTheEdges() throws {
        #expect(
            try html("> Alpha\nbravo\n>\n> Charlie")
                == "<p data-inset=\"1\">Alpha bravo</p><p data-inset=\"1\">Charlie</p>"
        )
    }

    @Test
    func setsCodeLineByLineKeepingItsIndent() throws {
        #expect(
            try html("```swift\nlet a = 1\n  b < c\n```")
                == "<p data-verse=\"1\" data-inset=\"1\">let a = 1<br>\u{2007}\u{2007}b &lt; c</p>"
        )
    }

    @Test
    func turnsARuleIntoASceneBreak() throws {
        #expect(
            try html("Alpha.\n\n---\n\nBravo.")
                == "<p>Alpha.</p><p style=\"text-align:center\">* * *</p><p>Bravo.</p>"
        )
    }

    @Test
    func writesATable() throws {
        let text = """
            | Alpha | Bravo |
            |:------|------:|
            | *Charlie* | 1 |
            | Delta \\| echo | |
            """

        #expect(
            try html(text)
                == [
                    "<table><thead><tr><th>Alpha</th><th style=\"text-align:right\">Bravo</th></tr></thead><tbody>",
                    "<tr><td><em>Charlie</em></td><td style=\"text-align:right\">1</td></tr>",
                    "<tr><td>Delta | echo</td><td style=\"text-align:right\"></td></tr>",
                    "</tbody></table>",
                ].joined()
        )
    }

    /// The table comes through the chapter vocabulary as a table, which is what the reader draws.
    @Test
    func writesATableTheReaderReadsAsOne() throws {
        let html = try html("Alpha.\n\n| Bravo | Charlie |\n|---|---|\n| 1 | 2 |\n")
        let table = try #require(BookHTML.chapter(from: html).paragraphs.last?.table)

        #expect(table.headerRows == 1)
        #expect(table.rows.map { $0.map(\.text) } == [ [ "Bravo", "Charlie" ], [ "1", "2" ] ])
    }

    @Test
    func turnsDownADocumentWithNothingInIt() {
        #expect(throws: BookFileError.self) { try book("\n\n<!-- nothing -->\n") }
    }

    @Test
    func namesTheBookAfterItsFirstHeading() throws {
        #expect(try book("Alpha bravo.\n\n## Charlie\n\nDelta.\n\n## Echo\n\nFoxtrot.").title == "Charlie")
    }

    /// A document with no heading at all is named by the words it opens with.
    @Test
    func namesAnUnheadedDocumentByItsOpeningWords() throws {
        #expect(try book("Alpha bravo.").title == "Alpha bravo.")
        #expect(
            try book("Alpha *bravo* charlie delta echo foxtrot, golf hotel.").title
                == "Alpha bravo charlie delta echo foxtrot…"
        )
    }

    /// Two untitled documents are two books, not one filed twice.
    @Test
    func filesAnUntitledDocumentByWhatItHolds() throws {
        #expect(try book("Alpha.").fingerprint != book("Bravo.").fingerprint)
        #expect(try book("# Charlie\n\nDelta.").fingerprint == book("# Charlie\n\nEcho.").fingerprint)
    }
}
