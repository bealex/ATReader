//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import Testing

@testable import BookKit

/// What the reader takes to be a note, and what it leaves as ordinary text.
///
/// The markup is invented, as everything in these tests is. What is being checked is the shape a note
/// takes, not any one book's spelling of it.
struct BookNoteTests {
    @Test
    func anAnchorIntoTheChapterIsANote() throws {
        let chapter = BookHTML.chapter(
            from: """
                <p>Kilo lima<a href="#n1">1</a> mike.</p>
                <p id="n1">A note about the lima.</p>
                """
        )

        #expect(chapter.paragraphs.count == 1)
        #expect(chapter.paragraphs[0].text == "Kilo lima1 mike.")

        let mark = try #require(chapter.paragraphs[0].notes.first)
        #expect(mark.range == NSRange(location: 9, length: 1))
        #expect(chapter.notes[mark.noteId]?.text == "A note about the lima.")
        #expect(chapter.notes[mark.noteId]?.marker == "1")
    }

    /// The whole point of leaving the marker alone: a reading position counts these characters.
    @Test
    func theMarkerKeepsTheCharactersTheTextGaveIt() {
        let noted = BookHTML.chapter(from: "<p>Kilo<a href=\"#n1\">[12]</a> lima.</p><p id=\"n1\">Note.</p>")
        let plain = BookHTML.chapter(from: "<p>Kilo[12] lima.</p>")

        #expect(noted.paragraphs[0].text == plain.paragraphs[0].text)
        #expect(noted.paragraphs[0].notes.first?.range == NSRange(location: 4, length: 4))
    }

    @Test
    func theBlockHoldingANoteLeavesTheChapter() {
        let chapter = BookHTML.chapter(
            from: """
                <p>November<a href="#n1">1</a>.</p>
                <p>Oscar papa.</p>
                <div id="n1"><p>The note.</p></div>
                """
        )

        #expect(chapter.paragraphs.map(\.text) == [ "November1.", "Oscar papa." ])
        #expect(chapter.notes.count == 1)
    }

    /// A note that opens with its own marker as a way back to the text: there is nowhere to go back to.
    @Test
    func aNoteDropsTheLinkBackToTheText() throws {
        let chapter = BookHTML.chapter(
            from: """
                <p>Quebec<a href="#n1">3</a>.</p>
                <p id="n1"><a href="#r1">3</a> Romeo sierra.</p>
                """
        )

        let mark = try #require(chapter.paragraphs[0].notes.first)
        #expect(chapter.notes[mark.noteId]?.text == "Romeo sierra.")
    }

    @Test
    func anAnchorCarryingItsOwnWordsIsANote() throws {
        let chapter = BookHTML.chapter(from: "<p>Tango<a title=\"Uniform victor.\">*</a> whiskey.</p>")

        let mark = try #require(chapter.paragraphs[0].notes.first)
        #expect(chapter.paragraphs[0].text == "Tango* whiskey.")
        #expect(chapter.notes[mark.noteId]?.text == "Uniform victor.")
    }

    @Test
    func twoNotesInOneParagraphAreBothPlaced() {
        let chapter = BookHTML.chapter(
            from: """
                <p>Xray<a href="#a">1</a> yankee<a href="#b">2</a>.</p>
                <p id="a">First.</p><p id="b">Second.</p>
                """
        )

        #expect(chapter.paragraphs[0].text == "Xray1 yankee2.")
        #expect(chapter.paragraphs[0].notes.map(\.location) == [ 4, 12 ])
        #expect(chapter.notes.count == 2)
    }

    /// A link out of the book is not a note, and is left as the text it always was.
    @Test
    func anOrdinaryLinkIsNotANote() {
        let chapter = BookHTML.chapter(from: "<p>Alfa <a href=\"https://example.com\">bravo</a> charlie.</p>")

        #expect(chapter.paragraphs[0].text == "Alfa bravo charlie.")
        #expect(chapter.paragraphs[0].notes.isEmpty)
        #expect(chapter.notes.isEmpty)
    }

    /// An anchor pointing at nothing this chapter carries stays text, rather than opening an empty popup.
    @Test
    func anAnchorWithNoNoteBehindItIsLeftAlone() {
        let chapter = BookHTML.chapter(from: "<p>Delta<a href=\"#gone\">1</a> echo.</p>")

        #expect(chapter.paragraphs[0].text == "Delta1 echo.")
        #expect(chapter.paragraphs[0].notes.isEmpty)
    }

    /// A note nothing points at would otherwise be a paragraph the reader silently lost.
    @Test
    func aBlockNothingPointsAtStaysInTheChapter() {
        let chapter = BookHTML.chapter(from: "<p>Foxtrot.</p><p id=\"loose\">Golf hotel.</p>")

        #expect(chapter.paragraphs.map(\.text) == [ "Foxtrot.", "Golf hotel." ])
        #expect(chapter.notes.isEmpty)
    }

    /// A note is named by its figure where it is shown, so the same figure at the head of its words
    /// would read as the note's first word.
    @Test
    func aNoteDropsTheFigureThatNamesIt() throws {
        let chapter = BookHTML.chapter(
            from: """
                <p>Alfa<a href="#n15">[15]</a>.</p>
                <p id="n15">15 Bravo charlie delta.</p>
                """
        )

        let mark = try #require(chapter.paragraphs[0].notes.first)
        #expect(chapter.notes[mark.noteId]?.marker == "[15]")
        #expect(chapter.notes[mark.noteId]?.text == "Bravo charlie delta.")
    }

    /// Only the figure that named it goes. A note opening on some other number keeps it.
    @Test
    func aNoteKeepsANumberThatIsNotItsOwn() throws {
        let chapter = BookHTML.chapter(
            from: """
                <p>Echo<a href="#n2">2</a>.</p>
                <p id="n2">1920 was the year.</p>
                """
        )

        let mark = try #require(chapter.paragraphs[0].notes.first)
        #expect(chapter.notes[mark.noteId]?.text == "1920 was the year.")
    }

    @Test
    func aTagThatMerelyStartsWithAIsNotAnAnchor() {
        let chapter = BookHTML.chapter(from: "<p>India <abbr title=\"juliett\">JLT</abbr> kilo.</p>")

        #expect(chapter.paragraphs[0].text == "India JLT kilo.")
        #expect(chapter.paragraphs[0].notes.isEmpty)
    }
}
