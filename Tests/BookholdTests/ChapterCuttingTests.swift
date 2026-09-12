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
    }

    /// A heading of nothing but marks is a break between scenes, and no place to start a chapter.
    @Test
    func leavesABookWhoseHeadingsAreSceneBreaks() throws {
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
        // The breaks stay where they stood, as subtitles in the one chapter's own text.
        #expect(read.sections.first?.html.contains("<h2>***</h2>") == true)
    }

    /// A file that already says where its chapters are is left alone.
    @Test
    func leavesABookThatHasSections() throws {
        let read = try book("""
            <section><title><p>Одна</p></title><p>Раз.</p><subtitle>Внутри</subtitle><p>Ещё.</p></section>
            <section><title><p>Другая</p></title><p>Два.</p></section>
            """)

        #expect(read.sections.count == 2)
        #expect(read.sections.map(\.title) == [ "Одна", "Другая" ])
    }
}
