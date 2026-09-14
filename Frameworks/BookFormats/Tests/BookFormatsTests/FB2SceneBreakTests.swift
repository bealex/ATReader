//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Foundation
import Testing

@testable import BookFormats

/// Where a break in the scene ends up, which is exactly where the book wrote it.
///
/// A book that parts its scenes with a subtitle rather than a blank line had every one of them read
/// as a heading, which cut the chapter in two at each break. The books here are written for the test.
struct FB2SceneBreakTests {
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

    private func blocks(_ read: ParsedBook, section: Int = 0) -> [Paragraph] {
        BookHTML.paragraphs(from: read.sections[section].html)
    }

    /// The asterism means a scene break and nothing else, so a subtitle holding one is a break.
    @Test
    func readsAnAsterismSubtitleAsABreakRatherThanAHeading() throws {
        let read = try book(
            """
            <section><title><p>Глава</p></title>\
            <p>Раз.</p><subtitle>⁂</subtitle><p>Два.</p></section>
            """
        )

        #expect(read.sections.count == 1, "the break cut the chapter in two")

        let blocks = blocks(read)

        #expect(blocks.contains { $0.isSceneBreak })
        #expect(!blocks.contains { $0.isSceneBreak && $0.titleLevel != nil })
    }

    /// The marks are the book's own. A file that parts its scenes with one asterism is not a file of
    /// star rows, and writing a row where it wrote a single mark puts words on the page nobody wrote.
    @Test
    func keepsTheMarksTheBookPartedItsScenesWith() throws {
        let read = try book("<section><p>Раз.</p><subtitle>⁂</subtitle><p>Два.</p></section>")
        let mark = blocks(read).first { $0.isSceneBreak }

        #expect(mark?.text == "⁂")
    }

    /// A blank line carries no marks of its own, so it is given the ones the service's chapters use.
    @Test
    func drawsABlankLineAsTheServicesOwnChaptersDo() throws {
        let read = try book("<section><p>Раз.</p><empty-line/><p>Два.</p></section>")
        let mark = blocks(read).first { $0.isSceneBreak }

        #expect(mark?.text == "* * *")
    }

    /// A subtitle that carries words names a part of its own and opens one, the way it always has.
    /// That is the behaviour a break must not borrow: a scene parted is not a part begun.
    @Test
    func letsASubtitleOfWordsOpenAPartOfItsOwn() throws {
        let read = try book(
            """
            <section><title><p>Глава</p></title>\
            <p>Раз.</p><subtitle>Вечер</subtitle><p>Два.</p></section>
            """
        )

        #expect(read.sections.count == 2)
        #expect(read.sections[1].title == "Вечер")
        #expect(!blocks(read).contains { $0.isSceneBreak })
    }

    /// The order the book wrote is the order the reader meets. A break before a picture stayed before
    /// it, where once the picture swallowed it.
    @Test
    func keepsABreakBeforeThePictureItStandsOver() throws {
        let read = try book(
            """
            <section><p>Раз.</p><empty-line/>\
            <image l:href="#plate.png"/><p>Два.</p></section>
            """
        )
        let blocks = blocks(read)
        let breakAt = blocks.firstIndex { $0.isSceneBreak }
        let plateAt = blocks.firstIndex { $0.imageSource != nil }

        #expect(breakAt != nil, "the picture swallowed the break")
        #expect(plateAt != nil)

        if let breakAt, let plateAt { #expect(breakAt < plateAt, "the break came out after the picture") }
    }

    @Test
    func keepsABreakAfterThePictureItFollows() throws {
        let read = try book(
            """
            <section><p>Раз.</p><image l:href="#plate.png"/>\
            <empty-line/><p>Два.</p></section>
            """
        )
        let blocks = blocks(read)

        if let breakAt = blocks.firstIndex(where: { $0.isSceneBreak }),
                let plateAt = blocks.firstIndex(where: { $0.imageSource != nil }) {
            #expect(plateAt < breakAt)
        } else {
            Issue.record("the break or the picture went missing")
        }
    }

    /// A run of blank lines parts two scenes once, not once for each line.
    @Test
    func collapsesARunOfBlankLinesIntoOneBreak() throws {
        let read = try book("<section><p>Раз.</p><empty-line/><empty-line/><empty-line/><p>Два.</p></section>")

        #expect(blocks(read).count { $0.isSceneBreak } == 1)
    }

    /// A break opening a section divides nothing, having nothing above it.
    @Test
    func writesNoBreakAtTheHeadOfASection() throws {
        let read = try book("<section><empty-line/><p>Раз.</p></section>")

        #expect(!blocks(read).contains { $0.isSceneBreak })
    }
}
