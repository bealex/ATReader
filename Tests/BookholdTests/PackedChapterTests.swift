//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import Foundation
import SQLite3
import Testing

@testable import Bookhold

/// A prepared chapter kept as bytes reads back as the chapter it was.
struct PackedChapterTests {
    @Test
    func everyFieldComesBack() throws {
        let chapter = Self.chapter()
        let read = try #require(ChapterContent(packed: chapter.packed()))

        #expect(read.paragraphs == chapter.paragraphs)
        #expect(read.hyphenated == chapter.hyphenated)
        #expect(read.language == chapter.language)
        #expect(read.notes == chapter.notes)
        #expect(read.readsRightToLeft == chapter.readsRightToLeft)
    }

    @Test
    func aChapterOfNothingComesBack() throws {
        let empty = ChapterContent(paragraphs: [], hyphenated: [], language: nil)
        let read = try #require(ChapterContent(packed: empty.packed()))

        #expect(read.paragraphs.isEmpty)
        #expect(read.language == nil)
    }

    @Test
    func oneChapterAlwaysPacksToTheSameBytes() {
        #expect(Self.chapter().packed() == Self.chapter().packed())
    }

    @Test
    func bytesThatStopShortReadAsNothing() {
        let packed = Self.chapter().packed()

        for length in stride(from: 0, to: packed.count, by: 7) {
            #expect(ChapterContent(packed: packed.prefix(length)) == nil, "read \(length) of \(packed.count) bytes")
        }
    }

    @Test
    func bytesInAnotherLayoutReadAsNothing() {
        var packed = Self.chapter().packed()

        packed[1] = 0xFF

        #expect(ChapterContent(packed: packed) == nil)
        #expect(ChapterContent(packed: Data("{\"paragraphs\":[]}".utf8)) == nil)
    }

    @Test
    func theStoreKeepsAChapterPacked() async throws {
        let (store, database) = Self.store()

        defer { try? FileManager.default.removeItem(at: database) }

        let chapter = Self.chapter()

        await store.store(
            prepared: PreparedChapter(chapterId: 7, contentHash: "hash", chainHash: "", content: chapter),
            workId: 1
        )

        let read = try #require(await store.preparedChapter(workId: 1, chapterId: 7, contentHash: "hash"))

        #expect(read.content.paragraphs == chapter.paragraphs)
        #expect(Self.text("SELECT content FROM chapter_content WHERE chapter_id = 7", in: database) == "")
        #expect(Self.number("SELECT LENGTH(packed) FROM chapter_content WHERE chapter_id = 7", in: database) > 0)
    }

    /// A chapter kept as JSON by an earlier build is read as it is, and packed for the next time.
    @Test
    func aChapterKeptAsJSONIsReadAndThenPacked() async throws {
        let (store, database) = Self.store()

        defer { try? FileManager.default.removeItem(at: database) }

        let chapter = Self.chapter()
        let json = try #require(String(bytes: try JSONEncoder().encode(chapter), encoding: .utf8))

        // Opens the file and makes its tables.
        _ = await store.books()
        Self.execute(
            """
            INSERT INTO chapter_content (chapter_id, work_id, content_hash, chain_hash, content, stored_at)
            VALUES (7, 1, 'hash', '', '\(json.replacingOccurrences(of: "'", with: "''"))', 0)
            """,
            in: database
        )

        let first = try #require(await store.preparedChapter(workId: 1, chapterId: 7, contentHash: "hash"))

        #expect(first.content.paragraphs == chapter.paragraphs)
        #expect(Self.text("SELECT content FROM chapter_content WHERE chapter_id = 7", in: database) == "")

        let second = try #require(await store.preparedChapter(workId: 1, chapterId: 7, contentHash: "hash"))

        #expect(second.content.hyphenated == chapter.hyphenated)
    }

    /// The whole library is packed in one go at the next launch, and that is done once.
    @Test
    func everyChapterKeptAsJSONIsPackedOnce() async throws {
        let (store, database) = Self.store()

        defer { try? FileManager.default.removeItem(at: database) }

        let json = try #require(String(bytes: try JSONEncoder().encode(Self.chapter()), encoding: .utf8))
            .replacingOccurrences(of: "'", with: "''")

        _ = await store.books()

        for chapterId in 1 ... 3 {
            Self.execute(Self.insert(chapterId, json), in: database)
        }

        Self.execute(Self.insert(4, "{ this was never a chapter"), in: database)

        await store.packKeptChapters()

        #expect(Self.number("SELECT COUNT(*) FROM chapter_content WHERE packed IS NOT NULL AND content = ''", in: database) == 3)
        // One that no longer reads goes, to be prepared again when it's wanted.
        #expect(Self.number("SELECT COUNT(*) FROM chapter_content", in: database) == 3)
        #expect(await store.preparedChapter(workId: 1, chapterId: 2, contentHash: "hash")?.content.paragraphs.count == 5)

        // Done once: a row that turns up as JSON afterwards is left for whoever reads it.
        Self.execute(Self.insert(9, json), in: database)
        await store.packKeptChapters()

        #expect(Self.number("SELECT COUNT(*) FROM chapter_content WHERE packed IS NULL", in: database) == 1)
    }

    private static func insert(_ chapterId: Int, _ json: String) -> String {
        """
        INSERT INTO chapter_content (chapter_id, work_id, content_hash, chain_hash, content, stored_at)
        VALUES (\(chapterId), 1, 'hash', '', '\(json)', 0)
        """
    }

    // MARK: - A chapter with something in every field

    private static func chapter() -> ChapterContent {
        let table = BookTable(
            rows: [
                [ .init(text: "Lorem", styles: [ .init(location: 0, length: 5, emphasis: .bold) ]), .init(text: "ipsum") ],
                [ .init(text: "dolor"), .init(text: "") ],
            ],
            headerRows: 1,
            alignments: [ .leading, .trailing, .center ]
        )
        let paragraphs = [
            Paragraph(id: 0, text: "Lorem ipsum dolor sit amet.", isCentered: false),
            Paragraph(
                id: 1,
                text: "Consectetur¹ adipiscing H2O elit — «sed» do.",
                isCentered: true,
                titleLevel: 2,
                notes: [ .init(location: 11, length: 1, noteId: "n1") ],
                scripts: [ .init(location: 25, length: 1, place: .below), .init(location: 3, length: 2, place: .above) ],
                styles: [ .init(location: 0, length: 11, emphasis: .italic), .init(location: 30, length: 4, emphasis: .bold) ],
                listLevel: 3,
                isRightToLeft: true,
                links: [ .init(location: 35, length: 5, target: "#place") ],
                anchor: "place",
                isRightAligned: true,
                isInset: true,
                isSource: true,
                isVerse: true
            ),
            Paragraph(id: 2, text: "", isCentered: false, imageSource: "book://-1/plate.png"),
            Paragraph(id: 3, text: "", isCentered: false, table: table),
            Paragraph(id: -4, text: "Эюя 日本語 🙂", isCentered: false, titleLevel: 0, listLevel: 0),
        ]
        let hyphenated = paragraphs.map { paragraph in
            Paragraph(
                id: paragraph.id,
                text: paragraph.text.replacingOccurrences(of: "o", with: "o\u{AD}"),
                isCentered: paragraph.isCentered
            )
        }

        return ChapterContent(
            paragraphs: paragraphs,
            hyphenated: hyphenated,
            language: "ru",
            notes: [
                "n1": BookNote(id: "n1", marker: "¹", text: "Sed ut perspiciatis."),
                "n2": BookNote(id: "n2", marker: "[2]", text: ""),
            ]
        )
    }

    // MARK: - Looking into the file

    private static func store() -> (SQLiteBookStore, URL) {
        let database = FileManager.default.temporaryDirectory
            .appendingPathComponent("packed-\(UUID().uuidString).sqlite")

        return (SQLiteBookStore(fileURL: database), database)
    }

    private static func execute(_ query: String, in database: URL) {
        var handle: OpaquePointer?

        guard sqlite3_open(database.path, &handle) == SQLITE_OK else { return }

        defer { sqlite3_close(handle) }

        sqlite3_exec(handle, query, nil, nil, nil)
    }

    private static func text(_ query: String, in database: URL) -> String? {
        row(query, in: database) { sqlite3_column_text($0, 0).map { String(cString: $0) } }
    }

    private static func number(_ query: String, in database: URL) -> Int {
        row(query, in: database) { Int(sqlite3_column_int64($0, 0)) } ?? 0
    }

    private static func row<Value>(_ query: String, in database: URL, read: (OpaquePointer?) -> Value?) -> Value? {
        var handle: OpaquePointer?
        var statement: OpaquePointer?

        guard sqlite3_open(database.path, &handle) == SQLITE_OK else { return nil }

        defer {
            sqlite3_finalize(statement)
            sqlite3_close(handle)
        }

        guard sqlite3_prepare_v2(handle, query, -1, &statement, nil) == SQLITE_OK, sqlite3_step(statement) == SQLITE_ROW
        else { return nil }

        return read(statement)
    }
}
