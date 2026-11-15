//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import CryptoKit
import Foundation
import Memoirs

public enum ArchiveError: Error, Sendable, Equatable, CustomStringConvertible {
    case unreadable
    case copyFailed(String)
    case noBackupThere
    case fromAnotherVersion(Int)

    public var description: String {
        switch self {
            case .unreadable: "the library could not be opened"
            case let .copyFailed(reason): "the copy failed: \(reason)"
            case .noBackupThere: "there is no backup in that folder"
            case let .fromAnotherVersion(version): "that backup was written by version \(version)"
        }
    }
}

/// Everything the device holds, written into a folder the reader chose, and read back from it.
///
/// The store is deliberately kept out of the device's own backup: it is all re-fetchable from the
/// service, and a chapter kept for reading offline has no business going through iCloud on its own. A
/// book imported from a file is the exception, and the reason this exists — nothing else on the device
/// holds it, so nothing else can give it back.
public enum LibraryArchive {
    /// What a backup says about itself, so a restore knows what it is about to put back.
    public struct Manifest: Codable, Sendable, Equatable {
        public let version: Int
        public let writtenAt: Date
        /// How much was written, for a reader deciding whether to trust it.
        public let bytes: Int64
        /// Every file written, by its path inside the backup: `library.sqlite`, `Books/12/book.fb2`.
        /// Nothing for a backup written before files were recorded.
        public let files: [String: FileEntry]?

        public init(
            version: Int = LibraryArchive.version,
            writtenAt: Date = .now,
            bytes: Int64,
            files: [String: FileEntry]? = nil
        ) {
            self.version = version
            self.writtenAt = writtenAt
            self.bytes = bytes
            self.files = files
        }
    }

    /// One file as the backup holds it.
    public struct FileEntry: Codable, Sendable, Equatable {
        public let size: Int64
        /// Its modification date, in seconds since 1970.
        public let modified: Double
        public let sha256: String
    }

    /// Bumped when what is written stops being readable by an older app.
    public static let version = 1

    private static let memoir = TracedMemoir(label: "archive", memoir: rootMemoir)

    /// The app keeps to one folder of its own inside whatever the reader picked, so a backup can sit
    /// beside their own files without burying them.
    public static func home(in folder: URL) -> URL {
        folder.appendingPathComponent("Bookhold", isDirectory: true)
    }

    private static func database(in folder: URL) -> URL { home(in: folder).appendingPathComponent("library.sqlite") }

    private static func books(in folder: URL) -> URL {
        home(in: folder).appendingPathComponent("Books", isDirectory: true)
    }

    private static func note(in folder: URL) -> URL { home(in: folder).appendingPathComponent("backup.json") }

    // MARK: - Writing one

    /// Copies the whole library into the folder, replacing whatever this app left there before.
    ///
    /// The caller holds the folder's security scope: a URL a reader picked stops working the moment it
    /// is given up, and this has no way to ask for it again.
    ///
    /// - Parameter books: where the device keeps the files of the books it imported.
    @discardableResult
    public static func write(
        to folder: URL,
        store: SQLiteBookStore,
        books: URL = LocalBookFiles.directory
    ) async throws -> Manifest {
        let files = FileManager.default
        let earlier = manifest(in: folder)?.files ?? [:]

        try files.createDirectory(at: home(in: folder), withIntermediateDirectories: true)
        try await store.copy(to: database(in: folder))

        // Everything an imported book brought with it: its own file, its cover, its pictures. Brought
        // into step rather than thrown away and written again: the whole of it runs to hundreds of
        // megabytes, and a backup that empties itself before it fills is no backup while it does.
        try sync(books, to: Self.books(in: folder))

        var entries = try Self.entries(in: books, under: booksKey, reusing: earlier)

        entries[databaseKey] = try entry(for: database(in: folder), reusing: nil)

        let manifest = Manifest(bytes: DiskSpace.taken(by: home(in: folder)), files: entries)

        try JSONEncoder().encode(manifest).write(to: note(in: folder), options: .atomic)
        memoir.info("wrote a backup of \(safe: manifest.bytes) bytes")
        return manifest
    }

    private static let databaseKey = "library.sqlite"
    private static let booksKey = "Books"

    /// Every file under a folder, keyed by its path beneath `prefix`.
    private static func entries(
        in folder: URL,
        under prefix: String,
        reusing earlier: [String: FileEntry]
    ) throws -> [String: FileEntry] {
        let files = FileManager.default
        var found: [String: FileEntry] = [:]
        let items = (try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: [ .isDirectoryKey ])) ?? []

        for item in items {
            let key = "\(prefix)/\(item.lastPathComponent)"

            if (try? item.resourceValues(forKeys: [ .isDirectoryKey ]))?.isDirectory == true {
                found.merge(try entries(in: item, under: key, reusing: earlier)) { _, new in new }
            } else {
                found[key] = try entry(for: item, reusing: earlier[key])
            }
        }

        return found
    }

    /// A file's entry, hashed afresh unless the earlier one has its size and date: a backup holding a
    /// gigabyte of books would otherwise read every byte of it every time.
    private static func entry(for url: URL, reusing earlier: FileEntry?) throws -> FileEntry {
        guard
            let stamp = stamp(of: url)
        else {
            throw ArchiveError.copyFailed("\(url.lastPathComponent) can't be read")
        }

        let size = Int64(stamp[0])
        let modified = Double(stamp[1])

        if let earlier, earlier.size == size, earlier.modified == modified { return earlier }

        return FileEntry(size: size, modified: modified, sha256: try sha256(of: url))
    }

    // MARK: - Reading one back

    /// What the folder says it holds, or nothing where it holds no backup of this app's.
    public static func manifest(in folder: URL) -> Manifest? {
        guard let data = try? Data(contentsOf: note(in: folder)) else { return nil }

        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    /// Puts a backup back, in place of everything the device is holding now.
    ///
    /// Everything is copied beside what the device holds and checked whole first, so a restore that
    /// fails leaves the device as it was. The store is closed only for the swap and opens itself again
    /// on the next question asked of it.
    ///
    /// - Parameters:
    ///   - books: where the device keeps the files of the books it imported.
    ///   - progress: how much has been put back, `0…1`, told as the files land.
    @discardableResult
    public static func read(
        from folder: URL,
        store: SQLiteBookStore,
        books: URL = LocalBookFiles.directory,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> Manifest {
        guard let manifest = manifest(in: folder) else { throw ArchiveError.noBackupThere }
        guard manifest.version <= version else { throw ArchiveError.fromAnotherVersion(manifest.version) }

        let files = FileManager.default

        guard files.fileExists(atPath: database(in: folder).path) else { throw ArchiveError.noBackupThere }

        let tally = Tally(total: manifest.bytes, report: progress)
        let entries = manifest.files
        let databaseURL = URL(fileURLWithPath: await store.path)
        let stagedDatabase = URL(fileURLWithPath: databaseURL.path + "-restoring")
        let stagedBooks = books.deletingLastPathComponent().appendingPathComponent("Books-restoring", isDirectory: true)
        let hasBooks = files.fileExists(atPath: Self.books(in: folder).path)

        defer {
            try? files.removeItem(at: stagedDatabase)
            try? files.removeItem(at: stagedBooks)
        }

        try? files.removeItem(at: stagedDatabase)
        try fetch(database(in: folder), to: stagedDatabase, expecting: entries?[databaseKey], tally: tally)

        if hasBooks {
            try? files.removeItem(at: stagedBooks)
            try copyTree(
                Self.books(in: folder),
                to: stagedBooks,
                keeping: books,
                under: booksKey,
                restoring: Restoring(entries: entries, tally: tally)
            )
        }

        await store.close()

        // The journal beside a database belongs to the database that was there, and reading a restored
        // file against somebody else's journal is how a good backup turns into a broken library.
        for beside in [ "", "-wal", "-shm" ] {
            try? files.removeItem(at: URL(fileURLWithPath: databaseURL.path + beside))
        }

        try files.moveItem(at: stagedDatabase, to: databaseURL)

        if hasBooks { try swap(stagedBooks, into: books) }

        progress(1)
        memoir.info("put back a backup written \(safe: manifest.writtenAt)")
        return manifest
    }

    /// Puts a staged folder where another stands, or where it would stand.
    private static func swap(_ staged: URL, into place: URL) throws {
        let files = FileManager.default

        guard files.fileExists(atPath: place.path) else { return try files.moveItem(at: staged, to: place) }

        _ = try files.replaceItemAt(place, withItemAt: staged)
    }

    /// A folder copied a file at a time, so the copying can be counted.
    ///
    /// A file the device already holds as the backup has it is taken from the device instead, which
    /// costs nothing on the same disk and spares downloading it from wherever the backup lives. Matching
    /// is by hash where the backup recorded one, and by size and date for a backup that didn't.
    private static func copyTree(
        _ source: URL,
        to destination: URL,
        keeping held: URL,
        under prefix: String,
        restoring: Restoring
    ) throws {
        let files = FileManager.default

        try files.createDirectory(at: destination, withIntermediateDirectories: true)

        for item in try files.contentsOfDirectory(at: source, includingPropertiesForKeys: [ .isDirectoryKey ]) {
            let name = downloadedName(of: item.lastPathComponent)
            let key = "\(prefix)/\(name)"
            let from = source.appendingPathComponent(name)
            let onto = destination.appendingPathComponent(name)
            let mine = held.appendingPathComponent(name)

            if (try? item.resourceValues(forKeys: [ .isDirectoryKey ]))?.isDirectory == true {
                try copyTree(from, to: onto, keeping: mine, under: key, restoring: restoring)
            } else if holds(mine, as: restoring.entries?[key], or: from) {
                try files.copyItem(at: mine, to: onto)
                restoring.tally.add(Int(size(of: mine) ?? 0))
            } else {
                try fetch(from, to: onto, expecting: restoring.entries?[key], tally: restoring.tally)
            }
        }
    }

    /// Whether the device's own file is the one the backup holds.
    private static func holds(_ mine: URL, as entry: FileEntry?, or backedUp: URL) -> Bool {
        guard let entry else { return stamp(of: mine).map { $0 == stamp(of: backedUp) } ?? false }
        guard size(of: mine) == entry.size else { return false }

        return (try? sha256(of: mine)) == entry.sha256
    }

    /// One file, read through a coordinator, which brings a file iCloud holds only as a placeholder
    /// down to the device before handing it over, and checked whole once it has landed: against its
    /// hash where the backup recorded one, against the size of what was read where it didn't.
    private static func fetch(_ source: URL, to destination: URL, expecting entry: FileEntry?, tally: Tally) throws {
        var coordination: NSError?
        var copying: Error?

        NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges, error: &coordination) { url in
            do {
                try FileManager.default.copyItem(at: url, to: destination)
                try check(destination, against: entry, or: url)
                tally.add(Int(size(of: destination) ?? 0))
            } catch {
                copying = error
            }
        }

        if let failure = coordination ?? copying { throw failure }
    }

    private static func check(_ landed: URL, against entry: FileEntry?, or source: URL) throws {
        let name = landed.lastPathComponent

        guard
            let entry
        else {
            guard size(of: landed) == size(of: source) else { throw ArchiveError.copyFailed("\(name) came out short") }

            return
        }
        guard
            size(of: landed) == entry.size,
            try sha256(of: landed) == entry.sha256
        else {
            throw ArchiveError.copyFailed("\(name) isn't what the backup recorded")
        }
    }

    private static func size(of url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [ .fileSizeKey ]))?.fileSize.map(Int64.init)
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)

        defer { try? handle.close() }

        var hasher = SHA256()

        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The name of the file an iCloud placeholder stands for: `.book.fb2.icloud` is `book.fb2`.
    private static func downloadedName(of name: String) -> String {
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return name }

        return String(name.dropFirst().dropLast(".icloud".count))
    }

    /// What a restore checks each file against, and where it counts what it has copied.
    private struct Restoring {
        let entries: [String: FileEntry]?
        let tally: Tally
    }

    /// How much of a restore has been copied, told only when it has moved enough to show.
    private final class Tally {
        private let total: Double
        private let report: @Sendable (Double) -> Void
        private var copied: Double = 0
        private var told: Double = 0

        init(total: Int64, report: @escaping @Sendable (Double) -> Void) {
            self.total = Double(max(total, 1))
            self.report = report
        }

        func add(_ bytes: Int) {
            copied += Double(bytes)

            let share = min(1, copied / total)

            guard share - told >= Self.step else { return }

            told = share
            report(share)
        }

        private static let step = 0.005
    }

    /// Brings a folder into step with another: what is gone here goes there, and what has changed is
    /// written over.
    ///
    /// A file counts as unchanged where its size and its date both match, which is what every tool
    /// that syncs folders takes as the answer. Reading a gigabyte to prove a gigabyte has not changed
    /// costs more than the copying it saves.
    private static func sync(_ source: URL, to destination: URL) throws {
        let files = FileManager.default

        try files.createDirectory(at: destination, withIntermediateDirectories: true)

        let here = Set((try? files.contentsOfDirectory(atPath: source.path)) ?? [])
        let there = Set((try? files.contentsOfDirectory(atPath: destination.path)) ?? [])

        // Gone from the device, so gone from the backup. A copy that keeps everything it has ever
        // seen is a copy of nothing in particular.
        for name in there.subtracting(here) {
            try? files.removeItem(at: destination.appendingPathComponent(name))
        }

        for name in here {
            let from = source.appendingPathComponent(name)
            let onto = destination.appendingPathComponent(name)

            guard stamp(of: from) != stamp(of: onto) else { continue }

            try? files.removeItem(at: onto)
            try files.copyItem(at: from, to: onto)
        }
    }

    /// What says a file is the one already there: how big it is, and when it was last written.
    private static func stamp(of url: URL) -> [Int]? {
        guard
            let values = try? url.resourceValues(forKeys: [ .fileSizeKey, .contentModificationDateKey ]),
            let size = values.fileSize,
            let changed = values.contentModificationDate
        else { return nil }

        return [ size, Int(changed.timeIntervalSince1970) ]
    }
}
