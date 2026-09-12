//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookRenderer
import BookStorage
import Foundation
import SQLite3
import Testing

@testable import Bookhold

/// Every book in a library backup, read in and measured the way the reader measures one.
///
/// Books are the reader's and stay out of this repository, so everything is named in the environment and
/// these do nothing without it. `AT_BACKUP` is a backup folder, `AT_BACKUP_SETTINGS` a device report
/// whose setting the pages are laid out at, and `AT_BACKUP_LOG` a file each chapter is written to before
/// it is measured, so a layout that never returns names its chapter. `AT_BACKUP_ONLY` narrows the run to
/// a comma-separated list of file names and work ids.
///
///     TEST_RUNNER_AT_BACKUP=~/…/Backup/Bookhold \
///     TEST_RUNNER_AT_BACKUP_SETTINGS=~/Downloads/reader-… \
///     TEST_RUNNER_AT_BACKUP_LOG=$PWD/build/backup.log \
///     Scripts/app.sh test --only BookholdTests/BackupBooksTests
@MainActor
struct BackupBooksTests {
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// Longer than this for one chapter is a layout worth looking at, even though it came back.
    private static let slow = Duration.seconds(5)

    /// Every book file the backup kept, read again by this build's parser and then measured.
    @Test
    func everyFileIsReadAndMeasured() async throws {
        guard let backup = Self.backup, let setting = Self.setting else { return }

        let files = try FileManager.default
            .contentsOfDirectory(at: backup.appendingPathComponent("Books"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "fb2z" && Self.isWanted($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let store = SQLiteBookStore(fileURL: Self.scratch("files.sqlite"))
        var faults: [String] = []

        for file in files {
            do {
                // Kept the way `LocalBookFiles` keeps a book: the file as picked, squeezed with zlib.
                let kept = try (Data(contentsOf: file) as NSData).decompressed(using: .zlib) as Data
                let read = try await BookImporting.read(kept)
                let book = await BookImporting.install(read, origin: BookOrigin(source: .file), store: store)

                faults += await measure(book.id, named: file.lastPathComponent, in: store, at: setting)
            } catch {
                faults.append("\(file.lastPathComponent): not read, \(error)")
            }
        }

        Self.log("files: \(files.count) read, \(faults.count) faults")
        #expect(faults.isEmpty, "\(faults.joined(separator: "\n"))")
    }

    /// Every book from the service in the backup's own store, its text prepared again from what it holds.
    @Test
    func everyStoredBookIsMeasured() async throws {
        guard let backup = Self.backup, let setting = Self.setting else { return }

        let copy = Self.scratch("library.sqlite")

        try FileManager.default.copyItem(at: backup.appendingPathComponent("library.sqlite"), to: copy)
        // What the device prepared and measured is dropped, so every chapter is set again by this build.
        Self.execute("DELETE FROM chapter_content; DELETE FROM chapter_placement;", in: copy)

        let store = SQLiteBookStore(fileURL: copy)
        let books = await store.books().filter { !BookNumbering.isLocal($0.id) && Self.isWanted("\($0.id)") }
        var faults: [String] = []

        for book in books {
            faults += await measure(book.id, named: "\(book.id)", in: store, at: setting)
        }

        Self.log("stored: \(books.count) measured, \(faults.count) faults")
        #expect(faults.isEmpty, "\(faults.joined(separator: "\n"))")
    }

    /// Measures a book one chapter at a time, as the reader's pass does, and says what went wrong.
    private func measure(
        _ workId: Int,
        named name: String,
        in store: SQLiteBookStore,
        at context: ChapterLayout.Context
    ) async -> [String] {
        let chapters = await store.chapters(workId: workId).filter(\.isReadable)
        let processor = BookProcessor(store: store)
        let pagination = BookPagination.make(workId: workId, context: context, store: store)
        let bodies = await store.storedBodyIds(workId: workId)
        var faults: [String] = []

        for (index, chapter) in chapters.enumerated() {
            Self.log("\(name) \(workId) chapter \(index + 1)/\(chapters.count) id \(chapter.id)")

            let content = await processor.content(workId: workId, chapterId: chapter.id)
            let started = ContinuousClock.now

            await pagination.measure(chapters: chapters, through: index + 1, content: { _ in content })

            let took = started.duration(to: .now)
            let pages = pagination.placement(of: chapter.id)?.pageCount ?? 0

            Self.log("  \(pages) pages in \(took.formatted(.units(allowed: [ .seconds, .milliseconds ])))")

            let place = "\(name) chapter \(index + 1) id \(chapter.id)"

            if content == nil, bodies.contains(chapter.id) {
                faults.append("\(place): its text is stored but nothing was prepared from it")
            }

            if let content, content.paragraphs.contains(where: { !$0.text.isEmpty || $0.isImage }), pages == 0 {
                faults.append("\(place): text but no pages")
            }

            if took > Self.slow { faults.append("\(place): took \(took)") }
        }

        return faults
    }

    // MARK: - Where things are

    /// Whether `AT_BACKUP_ONLY` leaves this book in, where it names any at all.
    private static func isWanted(_ name: String) -> Bool {
        guard let only = environment["AT_BACKUP_ONLY"] else { return true }

        return only.split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces) == name }
    }

    private static var backup: URL? {
        environment["AT_BACKUP"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }

    /// The report's setting, checked against the fingerprint the device wrote for it.
    private static var setting: ChapterLayout.Context? {
        guard
            let path = environment["AT_BACKUP_SETTINGS"],
            let read = PageReport.setting(ofReportAt: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        else { return nil }

        #expect(read.fingerprint == nil || read.fingerprint == read.context.fingerprint)

        return read.context
    }

    private static func scratch(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("backup-\(UUID().uuidString)-\(name)")
    }

    private static func log(_ line: String) {
        guard
            let path = environment["AT_BACKUP_LOG"],
            let data = "\(line)\n".data(using: .utf8)
        else { return }

        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }

    private static func execute(_ sql: String, in file: URL) {
        var database: OpaquePointer?

        guard sqlite3_open(file.path, &database) == SQLITE_OK else { return }

        sqlite3_exec(database, sql, nil, nil, nil)
        sqlite3_close(database)
    }
}
