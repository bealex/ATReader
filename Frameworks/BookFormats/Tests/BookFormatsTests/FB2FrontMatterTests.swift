//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Foundation
import Testing

@testable import BookFormats

/// What a `<body>` holds before its first section: the plate and epigraphs a book opens with.
///
/// The books here are written for the test.
struct FB2FrontMatterTests {
    private func book(_ body: String, coverpage: String = "") throws -> ParsedBook {
        let document = """
            <?xml version="1.0" encoding="utf-8"?>
            <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
              <description><title-info><book-title>Проба</book-title>\(coverpage)</title-info></description>
              <body>\(body)</body>
            </FictionBook>
            """

        return try FB2Parser.parse(Data(document.utf8))
    }

    /// What a book opens with stands ahead of its first chapter rather than falling out of it.
    @Test
    func opensWithWhatStandsBeforeTheFirstSection() throws {
        let read = try book(
            """
            <epigraph><p>Тудым и сюдым.</p><text-author>Некто</text-author></epigraph>
            <epigraph><p>Обратно тудым.</p></epigraph>
            <section><title><p>Глава</p></title><p>Раз.</p></section>
            """
        )

        #expect(read.sections.count == 2)
        #expect(read.sections.map(\.title) == [ nil, "Глава" ])
        #expect(read.sections.map(\.level) == [ 1, 1 ])
        #expect(read.sections[0].html.contains("Тудым и сюдым."))
        #expect(read.sections[0].html.contains("Некто"))
        #expect(read.sections[0].html.contains("Обратно тудым."))
        #expect(read.sections[0].textLength > 0)
    }

    /// A body's own title names the book, which the reader shows before the first page anyway.
    @Test
    func dropsTheTitleTheBodyGivesTheBook() throws {
        let read = try book(
            """
            <title><p>Некто</p><p>Проба</p></title>
            <epigraph><p>Тудым.</p></epigraph>
            <section><title><p>Глава</p></title><p>Раз.</p></section>
            """
        )

        #expect(read.sections.map(\.title) == [ nil, "Глава" ])
        #expect(read.sections.allSatisfy { !$0.html.contains("Некто") })
        #expect(read.sections.allSatisfy { !$0.html.contains("Проба") })
    }

    /// A body that opens straight onto its first section gains no page of its own.
    @Test
    func addsNothingWhereABodyOpensOnItsFirstSection() throws {
        let read = try book("<section><title><p>Глава</p></title><p>Раз.</p></section>")

        #expect(read.sections.map(\.title) == [ "Глава" ])
    }

    /// A title is not something to read, so a body carrying only one opens on its first chapter.
    @Test
    func addsNothingForATitleAlone() throws {
        let read = try book(
            """
            <title><p>Проба</p></title>
            <section><title><p>Глава</p></title><p>Раз.</p></section>
            """
        )

        #expect(read.sections.map(\.title) == [ "Глава" ])
    }

    /// A book opening on the plate its description already named as the cover is not showing it twice.
    @Test
    func dropsAnOpeningPlateThatIsTheCover() throws {
        let read = try book(
            ##"<image l:href="#обложка"/><section><title><p>Глава</p></title><p>Раз.</p></section>"##,
            coverpage: ##"<coverpage><image l:href="#обложка"/></coverpage>"##
        )

        #expect(read.sections.map(\.title) == [ "Глава" ])
    }

    /// Any other plate a book opens with is one it meant to show.
    @Test
    func keepsAnOpeningPlateOfItsOwn() throws {
        let read = try book(
            ##"<image l:href="#карта"/><section><title><p>Глава</p></title><p>Раз.</p></section>"##,
            coverpage: ##"<coverpage><image l:href="#обложка"/></coverpage>"##
        )

        #expect(read.sections.count == 2)
        #expect(read.sections[0].html.contains(#"<img src="карта">"#))
    }

    /// Notes still come out of the body that holds them rather than being read as front matter.
    @Test
    func readsTheNotesBodyAsNotesStill() throws {
        let read = try book(
            """
            <epigraph><p>Тудым.</p></epigraph>
            <section><p>Раз<a l:href="#n1" type="note">[1]</a>.</p></section>
            </body><body name="notes">
            <section id="n1"><p>Сюдым.</p></section>
            """
        )

        #expect(read.sections.count == 2)
        #expect(read.sections[0].html.contains("Тудым."))
        #expect(read.sections[1].html.contains(#"<div id="n1">Сюдым.</div>"#))
    }
}
