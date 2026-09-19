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

/// Where the time goes between tapping a book and being able to turn its pages.
///
/// Books are the reader's and stay out of this repository, so this needs `AT_BACKUP`,
/// `AT_BACKUP_SETTINGS` and `AT_BACKUP_ONLY` and does nothing without them. Output goes to
/// `AT_BACKUP_LOG`.
@MainActor
struct OpeningCostTests {
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// Watches the main actor and says how long it was held at a stretch.
    ///
    /// Laying a chapter out runs there, so a stretch the beat cannot get in on is a stretch in which
    /// no gesture is recognised and no page turns.
    @MainActor
    private final class Heartbeat {
        private(set) var worst: Duration = .zero
        private(set) var blocked: Duration = .zero
        private(set) var stalls = 0
        private var task: Task<Void, Never>?

        private static let beat = Duration.milliseconds(8)
        private static let noticeable = Duration.milliseconds(100)

        func start() {
            task = Task { @MainActor in
                var last = ContinuousClock.now

                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.beat)

                    let now = ContinuousClock.now
                    let gap = last.duration(to: now) - Self.beat

                    if gap > Self.noticeable {
                        stalls += 1
                        blocked += gap
                    }

                    worst = max(worst, gap)
                    last = now
                }
            }
        }

        func stop() { task?.cancel() }
    }

    /// Opens one book the way the reader does and says what each part of it cost.
    @Test
    func openingABookIsAccountedFor() async throws {
        guard let backup = Self.backup, let setting = Self.setting, let wanted = Self.wanted else { return }

        let copy = Self.scratch("library.sqlite")

        try FileManager.default.copyItem(at: backup.appendingPathComponent("library.sqlite"), to: copy)
        // Everything the device had already worked out is dropped, so this is a book opened cold.
        Self.execute("DELETE FROM chapter_content;", in: copy)

        let store = SQLiteBookStore(fileURL: copy)
        let chapters = await store.chapters(workId: wanted).filter(\.isReadable)

        try #require(!chapters.isEmpty, "book \(wanted) has nothing to read")

        Self.say("book \(wanted): \(chapters.count) chapters")

        await Self.run("cold", workId: wanted, chapters: chapters, store: store, at: setting)
        await Self.run("warm", workId: wanted, chapters: chapters, store: store, at: setting)
    }

    /// Opens the book at every chapter and turns a few pages each way from there, timed and watched.
    ///
    /// The reader cuts a page when it is turned onto, so an opening costs the page opened on and the
    /// ones beside it; the book behind them is never measured.
    private static func run(
        _ name: String,
        workId: Int,
        chapters: [BookChapter],
        store: SQLiteBookStore,
        at context: ChapterLayout.Context
    ) async {
        let processor = BookProcessor(store: store)
        let book = BookLayout(
            chapters: chapters.enumerated().map { place, chapter in
                BookLayout.Chapter(
                    id: chapter.id,
                    heading: ChapterHeading.make(position: place + 1, title: chapter.title),
                    opensItsOwnPage: max(1, chapter.level ?? 1) <= 1
                )
            },
            context: context,
            content: { await processor.content(workId: workId, chapterId: $0) }
        )
        let beat = Heartbeat()
        let started = ContinuousClock.now
        var slowest: (chapter: Int, took: Duration) = (0, .zero)
        var turned = 0

        beat.start()

        for (index, chapter) in chapters.enumerated() {
            let step = ContinuousClock.now

            guard var ahead = await book.page(at: BookPosition(chapterId: chapter.id, offset: 0)) else { continue }

            let took = step.duration(to: .now)
            var behind = ahead

            if took > slowest.took { slowest = (index + 1, took) }

            for _ in 0 ..< turns {
                if let next = await book.page(after: ahead) {
                    ahead = next
                    turned += 1
                }

                if let previous = await book.page(before: behind) {
                    behind = previous
                    turned += 1
                }
            }
        }

        beat.stop()

        let total = started.duration(to: .now)

        say(
            """
            \(name): \(show(total)) for \(chapters.count) openings and \(turned) turns
              slowest opening chapter \(slowest.chapter) at \(show(slowest.took))
              main actor held past 100ms \(beat.stalls) times, \(show(beat.blocked)) in all, \
            worst \(show(beat.worst))
            """
        )
    }

    /// How many pages each opening is turned through in each direction.
    private static let turns = 5

    private static func show(_ duration: Duration) -> String {
        duration.formatted(.units(allowed: [ .seconds, .milliseconds ], fractionalPart: .show(length: 0)))
    }

    // MARK: - Where things are

    private static var backup: URL? {
        environment["AT_BACKUP"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }

    private static var wanted: Int? { environment["AT_BACKUP_ONLY"].flatMap { Int($0) } }

    private static var setting: ChapterLayout.Context? {
        guard
            let path = environment["AT_BACKUP_SETTINGS"],
            let read = PageReport.setting(ofReportAt: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        else { return nil }

        return read
    }

    private static func scratch(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("cost-\(UUID().uuidString)-\(name)")
    }

    private static func say(_ line: String) {
        print(line)

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
