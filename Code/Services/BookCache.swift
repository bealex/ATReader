//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import Foundation

/// On-disk copies of the books the reader is working through.
///
/// Two jobs: reading works offline, and giving the daily refresh a baseline to diff new chapters against.
/// Everything lives under Application Support and is excluded from backup — it is all re-fetchable.
actor BookCache {
    /// What the last sweep knew about a book, so the next one can tell which chapters are new.
    struct Snapshot: Codable, Sendable {
        var chapterIds: [Int]
        var checkedAt: Date
        var title: String

        /// Chapters present now that the previous sweep had not seen.
        func newChapters(against current: [Int]) -> [Int] {
            let known = Set(chapterIds)
            return current.filter { !known.contains($0) }
        }
    }

    static let shared = BookCache()

    private let root: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(root: URL? = nil) {
        let base =
            root
            ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("BookCache", isDirectory: true)

        self.root = base

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        excludeFromBackup(base)
    }

    // MARK: - Chapter bodies

    func chapter(workId: Int, chapterId: Int) -> ChapterText? {
        load(ChapterText.self, from: chapterURL(workId: workId, chapterId: chapterId))
    }

    func store(chapter: ChapterText, workId: Int) {
        save(chapter, to: chapterURL(workId: workId, chapterId: chapter.id))
    }

    func hasChapter(workId: Int, chapterId: Int) -> Bool {
        FileManager.default.fileExists(atPath: chapterURL(workId: workId, chapterId: chapterId).path)
    }

    // MARK: - Tables of contents

    func contents(workId: Int) -> [ChapterInfo]? {
        load([ ChapterInfo ].self, from: contentsURL(workId: workId))
    }

    func store(contents: [ChapterInfo], workId: Int) {
        save(contents, to: contentsURL(workId: workId))
    }

    // MARK: - The reading shelf

    func readingShelf() -> [WorkMetaInfo]? {
        load([ WorkMetaInfo ].self, from: root.appendingPathComponent("reading-shelf.json"))
    }

    func store(readingShelf: [WorkMetaInfo]) {
        save(readingShelf, to: root.appendingPathComponent("reading-shelf.json"))
    }

    // MARK: - New-chapter snapshots

    func snapshots() -> [Int: Snapshot] {
        load([ Int: Snapshot ].self, from: snapshotsURL) ?? [:]
    }

    func store(snapshots: [Int: Snapshot]) {
        save(snapshots, to: snapshotsURL)
    }

    private var snapshotsURL: URL { root.appendingPathComponent("snapshots.json") }

    // MARK: - Housekeeping

    /// Drops everything cached for a book — used when it leaves the reading shelf.
    func purge(workId: Int) {
        try? FileManager.default.removeItem(at: workDirectory(workId: workId))
    }

    /// Keeps only the books still being read, so an abandoned series stops taking up room.
    func retainOnly(workIds: Set<Int>) {
        let manager = FileManager.default

        guard let entries = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }

        for entry in entries where entry.hasDirectoryPath {
            guard let id = Int(entry.lastPathComponent), !workIds.contains(id) else { continue }

            try? manager.removeItem(at: entry)
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        excludeFromBackup(root)
    }

    /// Rough on-disk size, for the storage row in the profile screen.
    func diskUsage() -> Int64 {
        let manager = FileManager.default

        guard let walker = manager.enumerator(at: root, includingPropertiesForKeys: [ .fileSizeKey ]) else { return 0 }

        var total: Int64 = 0

        for case let url as URL in walker {
            let size = try? url.resourceValues(forKeys: [ .fileSizeKey ]).fileSize
            total += Int64(size ?? 0)
        }

        return total
    }

    // MARK: - Paths and serialisation

    private func workDirectory(workId: Int) -> URL {
        root.appendingPathComponent(String(workId), isDirectory: true)
    }

    private func contentsURL(workId: Int) -> URL {
        workDirectory(workId: workId).appendingPathComponent("contents.json")
    }

    private func chapterURL(workId: Int, chapterId: Int) -> URL {
        workDirectory(workId: workId).appendingPathComponent("chapter-\(chapterId).json")
    }

    private func load<Value: Decodable>(_ type: Value.Type, from url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        return try? decoder.decode(Value.self, from: data)
    }

    private func save(_ value: some Encodable, to url: URL) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard let data = try? encoder.encode(value) else { return }

        try? data.write(to: url, options: .atomic)
    }

    private nonisolated func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
