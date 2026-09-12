//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookFormats
import BookKit
import Foundation
import Testing

@testable import Librix

/// Notes read out of a file, which keeps them in a body of their own at the end.
///
/// The book is invented, as every book in these tests is. What is checked is that a note written far
/// from the chapter that points at it arrives with that chapter, and reads the way one from the
/// service does.
@MainActor
struct BookFileNoteTests {
    @Test
    func aNoteReachesTheChapterThatPointsAtIt() async throws {
        let read = try await FB2Format().read(Self.fb2())
        let section = try #require(read.book.sections.first)
        let chapter = BookHTML.chapter(from: section.html)

        let mark = try #require(chapter.paragraphs.flatMap(\.notes).first)
        #expect(chapter.notes[mark.noteId]?.text == "Выдуманное пояснение к первому слову.")
        #expect(chapter.notes[mark.noteId]?.marker == "1")
    }

    /// The marker keeps the characters the file gave it: a reading position counts them.
    @Test
    func theMarkerStaysInTheText() async throws {
        let read = try await FB2Format().read(Self.fb2())
        let section = try #require(read.book.sections.first)
        let chapter = BookHTML.chapter(from: section.html)

        #expect(chapter.paragraphs.first?.text == "Первый выдуманный абзац1 для этой проверки.")
    }

    /// A note body is not a chapter, so nothing of it is set as text.
    @Test
    func theNotesBodyIsNotAChapter() async throws {
        let read = try await FB2Format().read(Self.fb2())

        #expect(read.book.sections.count == 1)
        #expect(!(read.book.sections.first?.html.contains("<p>Выдуманное пояснение") ?? true))
    }

    /// One chapter, one note in a body of its own, and an anchor between them.
    private static func fb2() -> Data {
        let book = """
            <?xml version="1.0" encoding="utf-8"?>
            <FictionBook xmlns:l="http://www.w3.org/1999/xlink">
            <description><title-info>
            <book-title>Пример книги с примечанием</book-title><lang>ru</lang>
            <author><first-name>Имя</first-name><last-name>Фамилия</last-name></author>
            </title-info><document-info><id>\(UUID().uuidString)</id></document-info></description>
            <body><section><title><p>Глава первая</p></title>
            <p>Первый выдуманный абзац<a l:href="#note1" type="note">1</a> для этой проверки.</p>
            </section></body>
            <body name="notes"><section id="note1">
            <p>Выдуманное пояснение к первому слову.</p>
            </section></body>
            </FictionBook>
            """

        return Data(book.utf8)
    }
}
