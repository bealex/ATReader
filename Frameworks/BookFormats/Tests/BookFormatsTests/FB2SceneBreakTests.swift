//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Foundation
import Testing

@testable import BookFormats

/// Where a break in the scene ends up, and what it is drawn with.
///
/// Two rules hold it together. A break stands where the book wrote it, and it is drawn with the marks
/// the book used, never with any of the reader's own. The books here are written for the test.
struct FB2SceneBreakTests {
    private enum Place {
        case before
        case after
        case missing
    }

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

    /// Which side of the picture the break came out on, so a break may never cross one.
    private func place(of read: ParsedBook) -> Place {
        let blocks = blocks(read)

        guard
            let mark = blocks.firstIndex(where: { $0.isSceneBreak }),
            let plate = blocks.firstIndex(where: { $0.imageSource != nil })
        else { return .missing }

        return mark < plate ? .before : .after
    }

    /// The asterism means a scene break and nothing else, so a subtitle holding one is a break and the
    /// chapter stands whole.
    @Test
    func readsAnAsterismSubtitleAsABreakRatherThanAHeading() throws {
        let read = try book(
            """
            <section><title><p>Глава</p></title><p>Раз.</p><subtitle>⁂</subtitle><p>Два.</p></section>
            """
        )

        #expect(read.sections.count == 1, "the break cut the chapter in two")
        #expect(blocks(read).contains { $0.isSceneBreak })
        #expect(!blocks(read).contains { $0.isSceneBreak && $0.titleLevel != nil })
    }

    /// The marks are the book's own. A file that parts its scenes with one asterism is not a file of
    /// star rows, and writing a row where it wrote one mark puts on the page words nobody wrote.
    @Test
    func keepsTheMarksTheBookPartedItsScenesWith() throws {
        let read = try book("<section><p>Раз.</p><subtitle>⁂</subtitle><p>Два.</p></section>")

        #expect(blocks(read).first { $0.isSceneBreak }?.text == "⁂")
    }

    /// A blank line is a gap and holds no marks, so nothing is written for it.
    @Test
    func writesNothingForABlankLine() throws {
        let read = try book("<section><p>Раз.</p><empty-line/><p>Два.</p></section>")

        #expect(!blocks(read).contains { $0.isSceneBreak })
        #expect(blocks(read).map(\.text) == [ "Раз.", "Два." ])
    }

    /// The case that was reported: a book wrapping every plate in blank lines came out with a row of
    /// stars above and below each picture, and none of them were in the file.
    @Test
    func writesNoMarksAroundAPlateWrappedInBlankLines() throws {
        let read = try book(
            """
            <section><p>Раз.</p><empty-line/><image l:href="#plate.png"/><empty-line/><p>Два.</p></section>
            """
        )

        #expect(!blocks(read).contains { $0.isSceneBreak })
        #expect(blocks(read).count { $0.imageSource != nil } == 1)
    }

    /// A break stays on the side of the picture the book put it on. A picture is met where the file
    /// defines it and never before, or the reader is shown what happens next.
    @Test
    func keepsABreakOnTheSideOfThePictureTheBookPutItOn() throws {
        let before = try book(
            """
            <section><p>Раз.</p><subtitle>⁂</subtitle><image l:href="#plate.png"/><p>Два.</p></section>
            """
        )
        let after = try book(
            """
            <section><p>Раз.</p><image l:href="#plate.png"/><subtitle>⁂</subtitle><p>Два.</p></section>
            """
        )

        #expect(place(of: before) == .before, "the picture swallowed the break or stood in front of it")
        #expect(place(of: after) == .after)
    }

    /// Two breaks running together part one pair of scenes, not two.
    @Test
    func collapsesBreaksThatRunTogether() throws {
        let read = try book(
            """
            <section><p>Раз.</p><subtitle>⁂</subtitle><subtitle>⁂</subtitle><p>Два.</p></section>
            """
        )

        #expect(blocks(read).count { $0.isSceneBreak } == 1)
    }

    /// A break opening a section divides nothing, having nothing above it.
    @Test
    func writesNoBreakAtTheHeadOfASection() throws {
        let read = try book("<section><subtitle>⁂</subtitle><p>Раз.</p></section>")

        #expect(!blocks(read).contains { $0.isSceneBreak })
    }

    /// A subtitle that carries words names a part of its own and opens one, the way it always has.
    /// That is the behaviour a break must not borrow: a scene parted is not a part begun.
    @Test
    func letsASubtitleOfWordsOpenAPartOfItsOwn() throws {
        let read = try book(
            """
            <section><title><p>Глава</p></title><p>Раз.</p><subtitle>Вечер</subtitle><p>Два.</p></section>
            """
        )

        #expect(read.sections.count == 2)
        #expect(read.sections[1].title == "Вечер")
        #expect(!blocks(read).contains { $0.isSceneBreak })
    }
}
