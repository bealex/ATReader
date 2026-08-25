//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import Foundation
import OSLog
import SQLite3

/// The books, chapter lists, chapter bodies and reading positions this device keeps for itself.
///
/// Everything a screen shows comes from here first and from the service second, so the app opens and
/// reads with no network at all. One SQLite file under Application Support, excluded from backup: it is
/// all re-fetchable, and a book kept for offline reading should not go through iCloud.
actor LocalStore {
    /// Where a reader stopped in a book, as a character offset so it survives a change of font.
    struct ReadingPosition: Sendable, Equatable {
        let workId: Int
        let chapterId: Int
        let characterOffset: Int
        let updatedAt: Date
    }

    /// A book as this device knows it: what the lists draw, plus the tags the book page shows.
    struct StoredWork: Sendable {
        let summary: WorkSummary
        let tags: [String]
    }

    static let shared = LocalStore()

    private static let logger = Logger(subsystem: "com.lonelybytes.atreader", category: "store")

    private let fileURL: URL
    private var database: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        let base =
            FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Library", isDirectory: true)

        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = fileURL ?? base.appendingPathComponent("library.sqlite")
        Self.excludeFromBackup(base)
    }

    // MARK: - Books

    func works(in shelf: LibraryState? = nil) -> [WorkSummary] {
        let query =
            shelf == nil
            ? """
            SELECT payload, reading_progress FROM work
            WHERE library_state IS NOT NULL ORDER BY last_read_time DESC
            """
            : "SELECT payload, reading_progress FROM work WHERE library_state = ? ORDER BY last_read_time DESC"

        guard let statement = Statement(open(), query) else { return [] }

        if let shelf { statement.bind(1, shelf.rawValue) }

        var result: [WorkSummary] = []

        while statement.step() {
            guard var summary = decode(WorkSummary.self, statement.string(0)) else { continue }

            summary.readingProgress = progress(statement.number(1), or: summary.readingProgress)
            result.append(summary)
        }

        return result
    }

    func work(id: Int) -> StoredWork? {
        let query = "SELECT payload, tags, reading_progress FROM work WHERE id = ?"

        guard let statement = Statement(open(), query) else { return nil }

        statement.bind(1, id)

        guard statement.step(), var summary = decode(WorkSummary.self, statement.string(0)) else { return nil }

        summary.readingProgress = progress(statement.number(2), or: summary.readingProgress)
        return StoredWork(summary: summary, tags: decode([ String ].self, statement.string(1)) ?? [])
    }

    /// How far this device knows the reader has got.
    ///
    /// Its own figure wins outright wherever it has one. The service stores nothing it is sent, so what
    /// it reports is only ever what the reader did somewhere else, and that reaches this device as a
    /// position instead, which the column is derived from. Taking the larger of the two was what let one
    /// bad reading pin a book at 100% for good.
    private func progress(_ stored: Double?, or reported: Double?) -> Double? { stored ?? reported }

    /// Records where this device believes the reader has got to in a book, `0…1`.
    func store(progress: Double, workId: Int) {
        guard let statement = Statement(open(), "UPDATE work SET reading_progress = ? WHERE id = ?") else { return }

        statement.bind(1, min(1, max(0, progress)))
        statement.bind(2, workId)
        statement.execute()
    }

    /// Works a book's overall progress out again from where the reader stopped and how long its
    /// chapters are.
    ///
    /// A stored fraction goes stale the moment the author publishes, because all of yesterday's book is
    /// less than all of today's. The position is a character offset in a named chapter, which stays
    /// true, so the fraction is derived from it again every time the contents change.
    private func recomputeProgress(workId: Int) {
        guard let position = position(workId: workId) else { return }

        let readable = chapters(workId: workId).filter(\.isReadable)
        let total = readable.reduce(0) { $0 + ($1.textLength ?? 0) }

        // A chapter of unknown length cannot be weighed, and guessing at it would drag a book that was
        // marked read back off the Finished shelf. Leave the stored figure alone instead.
        guard
            total > 0,
            let index = readable.firstIndex(where: { $0.id == position.chapterId }),
            let length = readable[index].textLength
        else { return }

        let before = readable.prefix(index).reduce(0) { $0 + ($1.textLength ?? 0) }
        let read = before + min(position.characterOffset, length)
        store(progress: Double(read) / Double(total), workId: workId)
    }

    func store(work: WorkSummary, tags: [String]? = nil) {
        store(works: [ work ])

        guard let tags, let statement = Statement(open(), "UPDATE work SET tags = ? WHERE id = ?") else { return }

        statement.bind(1, encode(tags))
        statement.bind(2, work.id)
        statement.execute()
    }

    func store(works: [WorkSummary]) {
        let query = """
            INSERT INTO work (id, title, author, library_state, last_read_time, reading_progress, updated_at, payload)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                author = excluded.author,
                library_state = excluded.library_state,
                last_read_time = COALESCE(excluded.last_read_time, work.last_read_time),
                reading_progress = COALESCE(work.reading_progress, excluded.reading_progress),
                updated_at = excluded.updated_at,
                payload = excluded.payload
            """

        transaction {
            guard
                let statement = Statement(open(), query),
                let lookup = Statement(open(), "SELECT payload FROM work WHERE id = ?")
            else { return }

            for work in works {
                // Merged rather than replaced: the shelf and a book's own details each leave out what
                // the other carries, and the payload is one column holding both.
                let merged = storedWork(work.id, using: lookup).map(work.merged) ?? work

                statement.reset()
                statement.bind(1, merged.id)
                statement.bind(2, merged.title)
                statement.bind(3, merged.authorLine)
                statement.bind(4, merged.libraryState.flatMap { $0 == LibraryState.none ? nil : $0.rawValue })
                statement.bind(5, merged.lastReadTime?.timeIntervalSince1970)
                statement.bind(6, merged.readingProgress)
                statement.bind(7, Date.now.timeIntervalSince1970)
                statement.bind(8, encode(merged))
                statement.execute()
            }
        }
    }

    /// The book as the payload column already has it, read through a statement the caller reuses.
    private func storedWork(_ id: Int, using statement: Statement) -> WorkSummary? {
        statement.reset()
        statement.bind(1, id)

        guard statement.step() else { return nil }

        return decode(WorkSummary.self, statement.string(0))
    }

    /// Replaces the shelves wholesale, so a book removed on another device stops showing up here.
    func replaceLibrary(with works: [WorkSummary]) {
        store(works: works)

        let ids = works.map { String($0.id) }.joined(separator: ",")
        execute("DELETE FROM work WHERE library_state IS NOT NULL AND id NOT IN (\(ids.isEmpty ? "0" : ids))")
    }

    // MARK: - Chapters

    func chapters(workId: Int) -> [ChapterInfo] {
        let query = "SELECT payload FROM chapter WHERE work_id = ? ORDER BY sort_order ASC, id ASC"

        guard let statement = Statement(open(), query) else { return [] }

        statement.bind(1, workId)
        var result: [ChapterInfo] = []

        while statement.step() {
            guard let chapter = decode(ChapterInfo.self, statement.string(0)) else { continue }

            result.append(chapter)
        }

        return result
    }

    func store(chapters: [ChapterInfo], workId: Int) {
        let query = """
            INSERT INTO chapter (id, work_id, sort_order, is_readable, payload)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                work_id = excluded.work_id,
                sort_order = excluded.sort_order,
                is_readable = excluded.is_readable,
                payload = excluded.payload
            """

        transaction {
            guard let statement = Statement(open(), query) else { return }

            for (index, chapter) in chapters.enumerated() {
                statement.reset()
                statement.bind(1, chapter.id)
                statement.bind(2, workId)
                statement.bind(3, chapter.sortOrder ?? index)
                statement.bind(4, chapter.isReadable ? 1 : 0)
                statement.bind(5, encode(chapter))
                statement.execute()
            }
        }

        recomputeProgress(workId: workId)
    }

    /// The chapters the service now lists that this device has never seen.
    ///
    /// A book with nothing stored yet has no news to report: everything already published is not new.
    func unseenChapters(workId: Int, in current: [ChapterInfo]) -> [Int] {
        let known = Set(chapters(workId: workId).map(\.id))

        guard !known.isEmpty else { return [] }

        return current.filter(\.isReadable).map(\.id).filter { !known.contains($0) }
    }

    // MARK: - Chapter bodies

    func body(workId: Int, chapterId: Int) -> ChapterText? {
        let query = "SELECT title, html, last_modification_time FROM chapter_body WHERE chapter_id = ? AND work_id = ?"

        guard let statement = Statement(open(), query) else { return nil }

        statement.bind(1, chapterId)
        statement.bind(2, workId)

        guard statement.step(), let html = statement.string(1) else { return nil }

        return ChapterText(
            id: chapterId,
            title: statement.string(0),
            html: html,
            lastModificationTime: statement.date(2)
        )
    }

    func hasBody(workId: Int, chapterId: Int) -> Bool {
        guard
            let statement = Statement(open(), "SELECT 1 FROM chapter_body WHERE chapter_id = ? AND work_id = ?")
        else { return false }

        statement.bind(1, chapterId)
        statement.bind(2, workId)
        return statement.step()
    }

    func storedBodyIds(workId: Int) -> Set<Int> {
        guard
            let statement = Statement(open(), "SELECT chapter_id FROM chapter_body WHERE work_id = ?")
        else { return [] }

        statement.bind(1, workId)
        var result: Set<Int> = []

        while statement.step() { result.insert(statement.integer(0)) }

        return result
    }

    func store(body: ChapterText, workId: Int) {
        let query = """
            INSERT INTO chapter_body (chapter_id, work_id, title, html, last_modification_time, stored_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(chapter_id) DO UPDATE SET
                work_id = excluded.work_id,
                title = excluded.title,
                html = excluded.html,
                last_modification_time = excluded.last_modification_time,
                stored_at = excluded.stored_at
            """

        guard let statement = Statement(open(), query) else { return }

        statement.bind(1, body.id)
        statement.bind(2, workId)
        statement.bind(3, body.title)
        statement.bind(4, body.html)
        statement.bind(5, body.lastModificationTime?.timeIntervalSince1970)
        statement.bind(6, Date.now.timeIntervalSince1970)
        statement.execute()
    }

    // MARK: - Reading positions

    func position(workId: Int) -> ReadingPosition? {
        let query = "SELECT chapter_id, character_offset, updated_at FROM reading_position WHERE work_id = ?"

        guard let statement = Statement(open(), query) else { return nil }

        statement.bind(1, workId)

        guard statement.step() else { return nil }

        return ReadingPosition(
            workId: workId,
            chapterId: statement.integer(0),
            characterOffset: statement.integer(1),
            updatedAt: statement.date(2) ?? .now
        )
    }

    func store(position: ReadingPosition) {
        let query = """
            INSERT INTO reading_position (work_id, chapter_id, character_offset, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(work_id) DO UPDATE SET
                chapter_id = excluded.chapter_id,
                character_offset = excluded.character_offset,
                updated_at = excluded.updated_at
            """

        guard let statement = Statement(open(), query) else { return }

        statement.bind(1, position.workId)
        statement.bind(2, position.chapterId)
        statement.bind(3, position.characterOffset)
        statement.bind(4, position.updatedAt.timeIntervalSince1970)
        statement.execute()
        recomputeProgress(workId: position.workId)
    }

    // MARK: - Housekeeping

    /// Chapter bodies only. Book lists, contents and reading positions stay, since they cost almost
    /// nothing and are what makes the app usable offline.
    func clearDownloads() {
        execute("DELETE FROM chapter_body")
        execute("VACUUM")
    }

    func downloadSize() -> Int64 {
        guard let statement = Statement(open(), "SELECT SUM(LENGTH(html)) FROM chapter_body") else { return 0 }
        guard statement.step() else { return 0 }

        return Int64(statement.integer(0))
    }

    // MARK: - The database itself

    @discardableResult
    private func open() -> OpaquePointer? {
        if let database { return database }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX

        guard
            sqlite3_open_v2(fileURL.path, &handle, flags, nil) == SQLITE_OK
        else {
            Self.logger.error("could not open \(self.fileURL.lastPathComponent, privacy: .public)")
            return nil
        }

        database = handle
        execute("PRAGMA journal_mode = WAL")
        execute("PRAGMA synchronous = NORMAL")
        migrate()
        return handle
    }

    private func migrate() {
        createWorkTable()
        createChapterTables()
        createPositionTable()
        repairProgress()
    }

    private func createWorkTable() {
        execute(
            """
            CREATE TABLE IF NOT EXISTS work (
                id INTEGER PRIMARY KEY,
                title TEXT NOT NULL,
                author TEXT,
                library_state TEXT,
                last_read_time REAL,
                reading_progress REAL,
                updated_at REAL NOT NULL,
                tags TEXT,
                payload TEXT NOT NULL
            )
            """
        )
    }

    private func createChapterTables() {
        execute(
            """
            CREATE TABLE IF NOT EXISTS chapter (
                id INTEGER PRIMARY KEY,
                work_id INTEGER NOT NULL,
                sort_order INTEGER,
                is_readable INTEGER,
                payload TEXT NOT NULL
            )
            """
        )
        execute("CREATE INDEX IF NOT EXISTS chapter_by_work ON chapter (work_id, sort_order)")
        execute(
            """
            CREATE TABLE IF NOT EXISTS chapter_body (
                chapter_id INTEGER PRIMARY KEY,
                work_id INTEGER NOT NULL,
                title TEXT,
                html TEXT NOT NULL,
                last_modification_time REAL,
                stored_at REAL NOT NULL
            )
            """
        )
        execute("CREATE INDEX IF NOT EXISTS body_by_work ON chapter_body (work_id)")
    }

    private func createPositionTable() {
        execute(
            """
            CREATE TABLE IF NOT EXISTS reading_position (
                work_id INTEGER PRIMARY KEY,
                chapter_id INTEGER NOT NULL,
                character_offset INTEGER NOT NULL,
                updated_at REAL NOT NULL
            )
            """
        )
    }

    /// Rebuilds every stored progress figure once, on databases written before the column meant what it
    /// means now.
    ///
    /// The column used to hold whatever the service last reported, raised but never lowered. The service
    /// reports progress through the current chapter when it has no character offset to give, on a
    /// `0…100` scale that was read as `0…1`, so a reader a little way into any chapter was recorded as
    /// having finished the book and could never be recorded as anything else. Nothing that came from
    /// there is worth keeping. What the reader actually did survives in `reading_position`, which the
    /// column is derived from anyway, so it is thrown away and worked out again.
    private func repairProgress() {
        guard userVersion() < 1 else { return }

        execute("UPDATE work SET reading_progress = NULL")

        if let statement = Statement(open(), "SELECT work_id FROM reading_position") {
            var ids: [Int] = []

            while statement.step() { ids.append(statement.integer(0)) }

            for id in ids { recomputeProgress(workId: id) }
        }

        execute("PRAGMA user_version = 1")
    }

    private func userVersion() -> Int {
        guard let statement = Statement(open(), "PRAGMA user_version") else { return 0 }
        guard statement.step() else { return 0 }

        return statement.integer(0)
    }

    private func transaction(_ body: () -> Void) {
        execute("BEGIN IMMEDIATE")
        body()
        execute("COMMIT")
    }

    private func execute(_ query: String) {
        guard let database = open() else { return }
        guard sqlite3_exec(database, query, nil, nil, nil) != SQLITE_OK else { return }

        Self.logger.error("\(String(cString: sqlite3_errmsg(database)), privacy: .public)")
    }

    private func encode(_ value: some Encodable) -> String? {
        guard let data = try? encoder.encode(value) else { return nil }

        return String(bytes: data, encoding: .utf8)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, _ raw: String?) -> Value? {
        guard let raw else { return nil }

        return try? decoder.decode(Value.self, from: Data(raw.utf8))
    }

    private static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// A prepared statement, finalised when it goes out of scope.
    private final class Statement {
        private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        private var handle: OpaquePointer?

        init?(_ database: OpaquePointer?, _ query: String) {
            guard let database else { return nil }
            guard
                sqlite3_prepare_v2(database, query, -1, &handle, nil) == SQLITE_OK
            else {
                LocalStore.logger.error("\(String(cString: sqlite3_errmsg(database)), privacy: .public)")
                return nil
            }
        }

        deinit {
            sqlite3_finalize(handle)
        }

        @discardableResult
        func bind(_ index: Int32, _ value: Int?) -> Bool {
            guard let value else { return sqlite3_bind_null(handle, index) == SQLITE_OK }

            return sqlite3_bind_int64(handle, index, Int64(value)) == SQLITE_OK
        }

        @discardableResult
        func bind(_ index: Int32, _ value: Double?) -> Bool {
            guard let value else { return sqlite3_bind_null(handle, index) == SQLITE_OK }

            return sqlite3_bind_double(handle, index, value) == SQLITE_OK
        }

        @discardableResult
        func bind(_ index: Int32, _ value: String?) -> Bool {
            guard let value else { return sqlite3_bind_null(handle, index) == SQLITE_OK }

            return sqlite3_bind_text(handle, index, value, -1, Self.transient) == SQLITE_OK
        }

        /// True when the step produced a row.
        func step() -> Bool { sqlite3_step(handle) == SQLITE_ROW }

        func execute() { _ = sqlite3_step(handle) }

        func reset() {
            sqlite3_reset(handle)
            sqlite3_clear_bindings(handle)
        }

        func integer(_ column: Int32) -> Int { Int(sqlite3_column_int64(handle, column)) }

        func number(_ column: Int32) -> Double? {
            guard sqlite3_column_type(handle, column) != SQLITE_NULL else { return nil }

            return sqlite3_column_double(handle, column)
        }

        func date(_ column: Int32) -> Date? {
            guard sqlite3_column_type(handle, column) != SQLITE_NULL else { return nil }

            return Date(timeIntervalSince1970: sqlite3_column_double(handle, column))
        }

        func string(_ column: Int32) -> String? {
            guard let raw = sqlite3_column_text(handle, column) else { return nil }

            return String(cString: raw)
        }
    }
}
