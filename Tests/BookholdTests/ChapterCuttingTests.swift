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

    /// A heading of nothing but marks divides two scenes, not two chapters. It is written into the text
    /// where the book put it, and the chapter stands whole.
    ///
    /// It used to cut, which turned a book that parts every scene that way into a contents of a hundred
    /// and more unnamed pieces and swallowed the mark along the way.
    @Test
    func partsTheScenesAtAHeadingThatNamesNothing() throws {
        let read = try book("""
            <section>
              <p>Раз.</p>
              <subtitle>***</subtitle>
              <p>Два.</p>
              <subtitle>***</subtitle>
              <p>Три.</p>
            </section>
            """)

        #expect(read.sections.count == 1)

        let blocks = BookHTML.paragraphs(from: read.sections[0].html)

        #expect(blocks.count { $0.isSceneBreak } == 2)
        #expect(!blocks.contains { $0.titleLevel != nil })
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
