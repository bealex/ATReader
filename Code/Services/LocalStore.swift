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

    /// Where one chapter sat when the book was last measured at a given setting.
    struct StoredPlacement: Sendable {
        let startOffset: Double
        let pageCount: Int
        /// Where the chapter after this one begins, so a run of cached chapters can carry on without
        /// laying any of them out.
        let nextOffset: Double
    }

    /// A chapter's text after the typesetter has been through it, and the hashes that say whether it
    /// is still the text the reader was given.
    struct PreparedChapter: Sendable {
        let chapterId: Int
        /// The chapter's own source text, hashed.
        let contentHash: String
        /// This chapter's hash folded into every chapter before it. Equal chains mean equal books up
        /// to this point, which is what makes a re-run pick up where the last one stopped.
        let chainHash: String
        let content: ChapterContent
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

    /// How many library books the app is still following: still being written, or finished within
    /// `days`, and not yet read to the end.
    ///
    /// A book that was already complete when it reached the library never counts, however recently its
    /// author stopped, because the badge is for writing this device actually watched happen. Books
    /// imported from a file are numbered below zero and have no author still at work, so they are out
    /// too, as are catalogue books the reader only looked at, which have no shelf.
    func followedBookCount(finishedWithin days: Int = 14) -> Int {
        let cutoff = Date.now.addingTimeInterval(-Double(days) * 24 * 60 * 60).timeIntervalSince1970
        let query = """
            SELECT COUNT(*) FROM work
            WHERE library_state IS NOT NULL
              AND id > 0
              AND finished_when_added = 0
              AND (is_finished = 0 OR (finished_at IS NOT NULL AND finished_at >= ?))
              AND COALESCE(reading_progress, 0) < ?
            """

        guard let statement = Statement(open(), query) else { return 0 }

        statement.bind(1, cutoff)
        statement.bind(2, WorkSummary.readThreshold)

        guard statement.step() else { return 0 }

        return statement.integer(0)
    }

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

        let custom = customSeries()
        var result: [WorkSummary] = []

        while statement.step() {
            guard var summary = decode(WorkSummary.self, statement.string(0)) else { continue }

            summary.readingProgress = progress(statement.number(1), or: summary.readingProgress)
            result.append(filed(summary, by: custom))
        }

        return result
    }

    func work(id: Int) -> StoredWork? {
        let query = "SELECT payload, tags, reading_progress FROM work WHERE id = ?"

        guard let statement = Statement(open(), query) else { return nil }

        statement.bind(1, id)

        guard statement.step(), var summary = decode(WorkSummary.self, statement.string(0)) else { return nil }

        summary.readingProgress = progress(statement.number(2), or: summary.readingProgress)
        return StoredWork(
            summary: filed(summary, by: customSeries()),
            tags: decode([ String ].self, statement.string(1)) ?? []
        )
    }

    /// The book under the series the reader filed it in, where they filed it in one.
    ///
    /// Applied on the way out rather than written into the book, because the service replaces the whole
    /// payload every time it answers and would carry the reader's grouping away with it.
    private func filed(_ summary: WorkSummary, by custom: [Int: CustomSeries]) -> WorkSummary {
        guard let own = custom[summary.id] else { return summary }

        var result = summary
        result.seriesTitle = own.series
        result.seriesOrder = own.order
        return result
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
            INSERT INTO work (
                id, title, author, library_state, last_read_time, reading_progress, updated_at, payload,
                is_finished, finished_when_added, finished_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                author = excluded.author,
                library_state = excluded.library_state,
                last_read_time = COALESCE(excluded.last_read_time, work.last_read_time),
                reading_progress = COALESCE(work.reading_progress, excluded.reading_progress),
                updated_at = excluded.updated_at,
                payload = excluded.payload,
                is_finished = excluded.is_finished,
                -- finished_when_added is left alone: it records the state the book arrived in.
                -- The stamp is the first completion this device saw, and is dropped if the author
                -- reopens the book so a later completion dates itself again.
                finished_at = CASE
                    WHEN excluded.is_finished = 0 THEN NULL
                    ELSE COALESCE(work.finished_at, excluded.finished_at)
                END
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
                statement.bind(9, merged.isComplete ? 1 : 0)
                statement.bind(10, merged.isComplete ? 1 : 0)
                statement.bind(11, merged.isComplete ? Date.now.timeIntervalSince1970 : nil)
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
        // Books imported from a file are on no shelf the service knows, so they sit outside this.
        execute(
            """
            DELETE FROM work WHERE library_state IS NOT NULL
                AND id NOT IN (\(ids.isEmpty ? "0" : ids))
                AND id NOT IN (SELECT work_id FROM local_book)
            """
        )
    }

    // MARK: - Series the reader made

    /// A book's place in a series the reader put together.
    struct CustomSeries: Sendable, Equatable {
        let series: String
        let order: Int
    }

    /// Every book the reader has filed by hand.
    ///
    /// Kept apart from the book itself because the payload is replaced wholesale every time the service
    /// answers, and a grouping written into it would last until the next refresh.
    func customSeries() -> [Int: CustomSeries] {
        guard
            let statement = Statement(open(), "SELECT work_id, series, sort_order FROM book_series")
        else { return [:] }

        var result: [Int: CustomSeries] = [:]

        while statement.step() {
            guard let series = statement.string(1) else { continue }

            result[statement.integer(0)] = CustomSeries(series: series, order: statement.integer(2))
        }

        return result
    }

    /// Files a run of books as one series, in the order given.
    func store(series: String, workIds: [Int]) {
        let query = """
            INSERT INTO book_series (work_id, series, sort_order) VALUES (?, ?, ?)
            ON CONFLICT(work_id) DO UPDATE SET series = excluded.series, sort_order = excluded.sort_order
            """

        transaction {
            guard let statement = Statement(open(), query) else { return }

            for (index, workId) in workIds.enumerated() {
                statement.reset()
                statement.bind(1, workId)
                statement.bind(2, series)
                statement.bind(3, index)
                statement.execute()
            }
        }
    }

    /// Gives books back to whatever series the service or the file says they belong to.
    func removeFromCustomSeries(workIds: [Int]) {
        let ids = workIds.map(String.init).joined(separator: ",")

        execute("DELETE FROM book_series WHERE work_id IN (\(ids.isEmpty ? "0" : ids))")
    }

    // MARK: - Books this device owns

    /// The id a book imported from a file goes under, allocated once per file and kept.
    ///
    /// Service works count up from one, so local books count down from minus one and the two can never
    /// meet. A chapter takes an id from a block of its own beneath the book's, which is what keeps the
    /// chapter table's primary key unique across a library holding both kinds.
    func localBookId(fingerprint: String) -> Int {
        if let statement = Statement(open(), "SELECT work_id FROM local_book WHERE fingerprint = ?") {
            statement.bind(1, fingerprint)

            if statement.step() { return statement.integer(0) }
        }

        let next = nextLocalSequence()

        guard
            let insert = Statement(
                open(),
                "INSERT INTO local_book (work_id, fingerprint, imported_at) VALUES (?, ?, ?)"
            )
        else { return LocalBooks.workId(sequence: next) }

        let workId = LocalBooks.workId(sequence: next)
        insert.bind(1, workId)
        insert.bind(2, fingerprint)
        insert.bind(3, Date.now.timeIntervalSince1970)
        insert.execute()
        return workId
    }

    private func nextLocalSequence() -> Int {
        guard let statement = Statement(open(), "SELECT MIN(work_id) FROM local_book") else { return 1 }
        guard statement.step(), let lowest = statement.number(0) else { return 1 }

        return LocalBooks.sequence(workId: Int(lowest)) + 1
    }

    /// Drops every chapter of a book that isn't in the list, text and prepared text with it.
    ///
    /// A corrected file can be shorter than the one it replaces. Storing its chapters only writes the
    /// ones it has, so without this the chapters it dropped would stay in the contents for good.
    func removeChapters(workId: Int, keeping ids: [Int]) {
        let kept = ids.map(String.init).joined(separator: ",")
        let list = kept.isEmpty ? "0" : kept

        transaction {
            for table in [ "chapter_body", "chapter_content", "chapter_placement", "chapter" ] {
                let column = table == "chapter" ? "id" : "chapter_id"
                execute("DELETE FROM \(table) WHERE work_id = \(workId) AND \(column) NOT IN (\(list))")
            }
        }
    }

    func isLocalBook(id: Int) -> Bool {
        guard let statement = Statement(open(), "SELECT 1 FROM local_book WHERE work_id = ?") else { return false }

        statement.bind(1, id)
        return statement.step()
    }

    /// Takes a book off the device outright: its row, its contents, its text and where the reader was.
    ///
    /// Only a local book is ever removed this way. A service book taken off a shelf keeps its rows, so
    /// putting it back doesn't cost a fresh download.
    func removeBook(id: Int) {
        transaction {
            for table in [ "chapter_body", "chapter_content", "chapter_placement", "chapter", "reading_position" ] {
                if let statement = Statement(open(), "DELETE FROM \(table) WHERE work_id = ?") {
                    statement.bind(1, id)
                    statement.execute()
                }
            }

            for table in [ "work", "local_book" ] {
                let column = table == "work" ? "id" : "work_id"

                if let statement = Statement(open(), "DELETE FROM \(table) WHERE \(column) = ?") {
                    statement.bind(1, id)
                    statement.execute()
                }
            }
        }
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

    // MARK: - Chapter text the typesetter has already been through

    /// The prepared text for one chapter, where what is stored was made from the text now on the device.
    ///
    /// The caller passes the hash it expects. A chapter whose source has changed since it was prepared
    /// answers `nil` rather than yesterday's paragraphs, which is what makes a re-imported book pick up
    /// its new chapters without being told which ones they are.
    func preparedChapter(workId: Int, chapterId: Int, contentHash: String) -> PreparedChapter? {
        let query = """
            SELECT content_hash, chain_hash, content FROM chapter_content
            WHERE chapter_id = ? AND work_id = ? AND content_hash = ?
            """

        guard let statement = Statement(open(), query) else { return nil }

        statement.bind(1, chapterId)
        statement.bind(2, workId)
        statement.bind(3, contentHash)

        guard
            statement.step(),
            let stored = statement.string(0),
            let chain = statement.string(1),
            let content = decode(ChapterContent.self, statement.string(2))
        else { return nil }

        return PreparedChapter(chapterId: chapterId, contentHash: stored, chainHash: chain, content: content)
    }

    /// One chapter's own text hash, which is what a measuring run folds into its chain.
    func contentHash(workId: Int, chapterId: Int) -> String? {
        let query = "SELECT content_hash FROM chapter_content WHERE chapter_id = ? AND work_id = ?"

        guard let statement = Statement(open(), query) else { return nil }

        statement.bind(1, chapterId)
        statement.bind(2, workId)

        guard statement.step() else { return nil }

        return statement.string(0)
    }

    // MARK: - Chapters already measured

    /// Where a chapter sat last time the book was measured, if the book and the setting are both still
    /// the ones it was measured against.
    func placement(workId: Int, chapterId: Int, chain: String, style: String) -> StoredPlacement? {
        let query = """
            SELECT start_offset, page_count, next_offset FROM chapter_placement
            WHERE chapter_id = ? AND work_id = ? AND chain_hash = ? AND style_hash = ?
            """

        guard let statement = Statement(open(), query) else { return nil }

        statement.bind(1, chapterId)
        statement.bind(2, workId)
        statement.bind(3, chain)
        statement.bind(4, style)

        guard statement.step(), let start = statement.number(0), let next = statement.number(2) else { return nil }

        return StoredPlacement(startOffset: start, pageCount: statement.integer(1), nextOffset: next)
    }

    func store(
        placement: StoredPlacement,
        workId: Int,
        chapterId: Int,
        chain: String,
        style: String
    ) {
        let query = """
            INSERT INTO chapter_placement
                (chapter_id, style_hash, work_id, chain_hash, start_offset, page_count, next_offset, stored_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(chapter_id, style_hash) DO UPDATE SET
                work_id = excluded.work_id,
                chain_hash = excluded.chain_hash,
                start_offset = excluded.start_offset,
                page_count = excluded.page_count,
                next_offset = excluded.next_offset,
                stored_at = excluded.stored_at
            """

        guard let statement = Statement(open(), query) else { return }

        statement.bind(1, chapterId)
        statement.bind(2, style)
        statement.bind(3, workId)
        statement.bind(4, chain)
        statement.bind(5, placement.startOffset)
        statement.bind(6, placement.pageCount)
        statement.bind(7, placement.nextOffset)
        statement.bind(8, Date.now.timeIntervalSince1970)
        statement.execute()
    }

    func store(prepared: PreparedChapter, workId: Int) {
        let query = """
            INSERT INTO chapter_content (chapter_id, work_id, content_hash, chain_hash, content, stored_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(chapter_id) DO UPDATE SET
                work_id = excluded.work_id,
                content_hash = excluded.content_hash,
                chain_hash = excluded.chain_hash,
                content = excluded.content,
                stored_at = excluded.stored_at
            """

        guard let statement = Statement(open(), query) else { return }

        statement.bind(1, prepared.chapterId)
        statement.bind(2, workId)
        statement.bind(3, prepared.contentHash)
        statement.bind(4, prepared.chainHash)
        statement.bind(5, encode(prepared.content))
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
    ///
    /// A book imported from a file is left alone. The service can send its text again and this cannot:
    /// the copy here is the only one, and clearing it would throw the book away.
    func clearDownloads() {
        execute("DELETE FROM chapter_body WHERE work_id NOT IN (SELECT work_id FROM local_book)")
        execute("DELETE FROM chapter_content WHERE work_id NOT IN (SELECT work_id FROM local_book)")
        // Measurements are worked out again from text the device still has, so they always go.
        execute("DELETE FROM chapter_placement")
        execute("VACUUM")
    }

    func downloadSize() -> Int64 {
        let query = """
            SELECT
                (SELECT COALESCE(SUM(LENGTH(html)), 0) FROM chapter_body)
                + (SELECT COALESCE(SUM(LENGTH(content)), 0) FROM chapter_content)
            """

        guard let statement = Statement(open(), query) else { return 0 }
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
        createSeriesTable()
        createLocalBookTable()
        createContentTable()
        createPlacementTable()
        addCompletionColumns()
        repairProgress()
    }

    /// Adds the columns that date a book's writing, for a store made before they existed.
    ///
    /// A book already complete when this runs finished before the app ever watched it, which is the
    /// same thing as having been added complete, so it is marked that way and never counts.
    private func addCompletionColumns() {
        let existing = workColumns()

        guard !existing.contains("finished_when_added") else { return }

        execute("ALTER TABLE work ADD COLUMN is_finished INTEGER NOT NULL DEFAULT 0")
        execute("ALTER TABLE work ADD COLUMN finished_when_added INTEGER NOT NULL DEFAULT 0")
        execute("ALTER TABLE work ADD COLUMN finished_at REAL")

        guard let statement = Statement(open(), "SELECT id, payload FROM work") else { return }

        var complete: [Int] = []

        while statement.step() {
            guard let work = decode(WorkSummary.self, statement.string(1)), work.isComplete else { continue }

            complete.append(statement.integer(0))
        }

        guard !complete.isEmpty else { return }

        let ids = complete.map(String.init).joined(separator: ",")
        execute("UPDATE work SET is_finished = 1, finished_when_added = 1 WHERE id IN (\(ids))")
    }

    private func workColumns() -> Set<String> {
        guard let statement = Statement(open(), "PRAGMA table_info(work)") else { return [] }

        var names: Set<String> = []

        while statement.step() {
            guard let name = statement.string(1) else { continue }

            names.insert(name)
        }

        return names
    }

    private func createSeriesTable() {
        execute(
            """
            CREATE TABLE IF NOT EXISTS book_series (
                work_id INTEGER PRIMARY KEY,
                series TEXT NOT NULL,
                sort_order INTEGER NOT NULL
            )
            """
        )
    }

    private func createLocalBookTable() {
        execute(
            """
            CREATE TABLE IF NOT EXISTS local_book (
                work_id INTEGER PRIMARY KEY,
                fingerprint TEXT NOT NULL UNIQUE,
                imported_at REAL NOT NULL
            )
            """
        )
    }

    private func createPlacementTable() {
        execute(
            """
            CREATE TABLE IF NOT EXISTS chapter_placement (
                chapter_id INTEGER NOT NULL,
                style_hash TEXT NOT NULL,
                work_id INTEGER NOT NULL,
                chain_hash TEXT NOT NULL,
                start_offset REAL NOT NULL,
                page_count INTEGER NOT NULL,
                next_offset REAL NOT NULL,
                stored_at REAL NOT NULL,
                PRIMARY KEY (chapter_id, style_hash)
            )
            """
        )
        execute("CREATE INDEX IF NOT EXISTS placement_by_work ON chapter_placement (work_id)")
    }

    private func createContentTable() {
        execute(
            """
            CREATE TABLE IF NOT EXISTS chapter_content (
                chapter_id INTEGER PRIMARY KEY,
                work_id INTEGER NOT NULL,
                content_hash TEXT NOT NULL,
                chain_hash TEXT NOT NULL,
                content TEXT NOT NULL,
                stored_at REAL NOT NULL
            )
            """
        )
        execute("CREATE INDEX IF NOT EXISTS content_by_work ON chapter_content (work_id)")
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
                payload TEXT NOT NULL,
                is_finished INTEGER NOT NULL DEFAULT 0,
                finished_when_added INTEGER NOT NULL DEFAULT 0,
                finished_at REAL
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
