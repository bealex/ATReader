//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookFormats
import BookKit
import Foundation
import Testing

@testable import Bookhold

/// Where a file's chapters are, when the file does not say outright.
///
/// The books here are written for the test. A section apiece is what most files give; some keep the
/// whole text in one and mark their chapters inside it; some mark nothing at all.
struct ChapterCuttingTests {
    private func book(_ body: String) throws -> ParsedBook {
        let document = """
            <?xml version="1.0" encoding="utf-8"?>
            <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
              <description><title-info><book-title>Проба</book-title></title-info></description>
              <body>\(body)</body>
            </FictionBook>
            """

        return try FB2Parser.parse(Data(document.utf8))
    }

    /// One section carrying its chapters as headings is cut at them.
    @Test
    func cutsOneSectionAtItsHeadings() throws {
        let read = try book("""
            <section>
              <p>Перед началом.</p>
              <subtitle>Первая</subtitle>
              <p>Раз.</p>
              <subtitle>Вторая</subtitle>
              <p>Два.</p>
            </section>
            """)

        #expect(read.sections.count == 3)
        #expect(read.sections.map(\.title) == [ nil, "Первая", "Вторая" ])
        #expect(read.sections.map(\.level) == [ 1, 2, 2 ])
    }

    /// A heading of nothing but marks still divides the book. It names nothing, so the piece it opens
    /// carries no title, and the contents calls it what it is.
    @Test
    func cutsAtHeadingsThatNameNothing() throws {
        let read = try book("""
            <section>
              <p>Раз.</p>
              <subtitle>***</subtitle>
              <p>Два.</p>
              <subtitle>***</subtitle>
              <p>Три.</p>
            </section>
            """)

        #expect(read.sections.count == 3)
        #expect(read.sections.map(\.title) == [ nil, nil, nil ])
        // A piece cut out of a section stands one level below it.
        #expect(read.sections.map(\.level) == [ 1, 2, 2 ])
    }

    /// A file that names its chapters keeps those names, and what is marked inside one stands under it.
    @Test
    func cutsInsideASectionWithoutLosingItsName() throws {
        let read = try book("""
            <section><title><p>Одна</p></title><p>Раз.</p><subtitle>Внутри</subtitle><p>Ещё.</p></section>
            <section><title><p>Другая</p></title><p>Два.</p></section>
            """)

        #expect(read.sections.map(\.title) == [ "Одна", "Внутри", "Другая" ])
        #expect(read.sections.map(\.level) == [ 1, 2, 1 ])
    }
}
