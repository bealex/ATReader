//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Foundation
import Testing

@testable import BookFormats

/// What a file marks inside a paragraph, and how it sets the blocks it stands them in.
///
/// The books here are written for the test.
struct FB2MarkupTests {
    private func book(_ body: String) throws -> ParsedBook {
        let document = """
            <?xml version="1.0" encoding="utf-8"?>
            <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
              <description><title-info><book-title>Проба</book-title></title-info></description>
              <body>\(body)</body>
            </FictionBook>
            """

        return try FB2Parser.parse(Data(document.utf8))
    }

    private func first(_ body: String) throws -> String {
        try #require(book("<section><p>\(body)</p></section>").sections.first).html
    }

    @Test
    func keepsWordsTheFileSetApart() throws {
        #expect(try first("Раз <emphasis>два</emphasis> три.") == "<p>Раз <em>два</em> три.</p>")
        #expect(try first("Раз <strong>два</strong> три.") == "<p>Раз <strong>два</strong> три.</p>")
    }

    /// One inside another comes out nested rather than crossed.
    @Test
    func nestsOneMarkInsideAnother() throws {
        let html = try first("<emphasis>Раз <strong>два</strong> три</emphasis>.")

        #expect(html == "<p><em>Раз <strong>два</strong> три</em>.</p>")
    }

    /// The words keep the characters the file gave them, since a reading position counts them.
    @Test
    func addsNothingToTheWordsThemselves() throws {
        let read = try book("<section><p>Раз <strong>два</strong> три.</p></section>")
        let section = try #require(read.sections.first)

        #expect(section.textLength == "Раз два три.".count)
    }

    /// A marker pointing at a note is still a marker, standing beside words set apart.
    @Test
    func marksANoteBesideWordsSetApart() throws {
        let html = try first(##"Раз<a l:href="#n1" type="note">[1]</a> <emphasis>два</emphasis>."##)

        #expect(html == ##"<p>Раз<a href="#n1">[1]</a> <em>два</em>.</p>"##)
    }

    /// An epigraph is a passage quoted before the chapter it stands over, not a centred line.
    @Test
    func setsAnEpigraphAsAQuotation() throws {
        let read = try book(
            """
            <section>
              <title><p>Глава</p></title>
              <epigraph><p>Тудым.</p><text-author>Некто</text-author></epigraph>
              <p>Раз.</p>
            </section>
            """
        )
        let html = try #require(read.sections.first).html

        #expect(html.contains(#"<p data-inset="1">Тудым.</p>"#))
        // Whose words they were, marked as that rather than as more of them.
        #expect(html.contains(#"<p data-source="1" data-inset="1"><em>Некто</em></p>"#))
        #expect(html.contains("<p>Раз.</p>"))
        #expect(!html.contains("text-align:center"))
    }

    /// A poem says it is one, so its lines are marked as verse rather than being guessed at from how
    /// short they are.
    @Test
    func marksTheLinesOfAPoemAsVerse() throws {
        let read = try book("<section><poem><stanza><v>Тудым.</v><v>Сюдым.</v></stanza></poem></section>")
        let html = try #require(read.sections.first).html

        #expect(html.contains(#"data-verse="1""#))
        #expect(html.components(separatedBy: #"data-verse="1""#).count == 3)
    }

    /// A poem quoted as an epigraph is both: held off the edge because it is quoted, and verse because
    /// it is a poem. Taking only the first left it set as prose.
    @Test
    func marksAPoemQuotedAsAnEpigraphAsBoth() throws {
        let read = try book(
            """
            <section>
              <title><p>Глава</p></title>
              <epigraph><poem><stanza><v>Тудым.</v></stanza></poem><text-author>Некто</text-author></epigraph>
              <p>Раз.</p>
            </section>
            """
        )
        let html = try #require(read.sections.first).html

        #expect(html.contains(#"<p data-verse="1" data-inset="1">Тудым.</p>"#))
        // Whose words they were is not a line of the poem.
        #expect(html.contains(#"<p data-source="1" data-inset="1"><em>Некто</em></p>"#))
        #expect(html.contains("<p>Раз.</p>"))
    }

    /// A passage quoted inside a chapter is held off the edge the same way.
    @Test
    func setsACitationAsAQuotation() throws {
        let read = try book("<section><cite><p>Тудым.</p><text-author>Некто</text-author></cite><p>Раз.</p></section>")
        let html = try #require(read.sections.first).html

        #expect(
            html == #"<p data-inset="1">Тудым.</p><p data-source="1" data-inset="1"><em>Некто</em></p><p>Раз.</p>"#
        )
    }

    /// A poem is still set centred, which is the one place the file's own shape asks for it, and its
    /// lines are marked as verse as well.
    @Test
    func setsAPoemCentred() throws {
        let read = try book("<section><poem><stanza><v>Раз.</v></stanza></poem></section>")

        #expect(
            try #require(read.sections.first).html
                == #"<p data-verse="1" style="text-align:center">Раз.</p>"#
        )
    }
}
