//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import OSLog

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

        public init(version: Int = LibraryArchive.version, writtenAt: Date = .now, bytes: Int64) {
            self.version = version
            self.writtenAt = writtenAt
            self.bytes = bytes
        }
    }

    /// Bumped when what is written stops being readable by an older app.
    public static let version = 1

    private static let logger = Logger(subsystem: "com.lonelybytes.atreader", category: "archive")

    /// The app keeps to one folder of its own inside whatever the reader picked, so a backup can sit
    /// beside their own files without burying them.
    public static func home(in folder: URL) -> URL {
        folder.appendingPathComponent("Librix", isDirectory: true)
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
    @discardableResult
    public static func write(to folder: URL, store: SQLiteBookStore) async throws -> Manifest {
        let files = FileManager.default

        try files.createDirectory(at: home(in: folder), withIntermediateDirectories: true)
        try await store.copy(to: database(in: folder))

        // Everything an imported book brought with it: its own file, its cover, its pictures. Brought
        // into step rather than thrown away and written again: the whole of it runs to hundreds of
        // megabytes, and a backup that empties itself before it fills is no backup while it does.
        try sync(LocalBookFiles.directory, to: books(in: folder))

        let manifest = Manifest(bytes: size(of: home(in: folder)))

        try JSONEncoder().encode(manifest).write(to: note(in: folder), options: .atomic)
        logger.info("wrote a backup of \(manifest.bytes) bytes")
        return manifest
    }

    // MARK: - Reading one back

    /// What the folder says it holds, or nothing where it holds no backup of this app's.
    public static func manifest(in folder: URL) -> Manifest? {
        guard let data = try? Data(contentsOf: note(in: folder)) else { return nil }

        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    /// Puts a backup back, in place of everything the device is holding now.
    ///
    /// The store is closed first and opens itself again on the next question asked of it, so this is a
    /// matter of swapping files rather than of restarting the app.
    @discardableResult
    public static func read(from folder: URL, store: SQLiteBookStore) async throws -> Manifest {
        guard let manifest = manifest(in: folder) else { throw ArchiveError.noBackupThere }
        guard manifest.version <= version else { throw ArchiveError.fromAnotherVersion(manifest.version) }

        let files = FileManager.default

        guard files.fileExists(atPath: database(in: folder).path) else { throw ArchiveError.noBackupThere }

        await store.close()

        // The journal beside a database belongs to the database that was there, and reading a restored
        // file against somebody else's journal is how a good backup turns into a broken library.
        for beside in [ "", "-wal", "-shm" ] {
            try? files.removeItem(at: URL(fileURLWithPath: await store.path + beside))
        }

        try files.copyItem(at: database(in: folder), to: URL(fileURLWithPath: await store.path))

        if files.fileExists(atPath: books(in: folder).path) {
            try? files.removeItem(at: LocalBookFiles.directory)
            try files.copyItem(at: books(in: folder), to: LocalBookFiles.directory)
        }

        logger.info("put back a backup written \(manifest.writtenAt)")
        return manifest
    }

    /// How much a folder holds, walked rather than asked for: a directory reports its own size and not
    /// what is under it.
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

    private static func size(of folder: URL) -> Int64 {
        guard
            let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [ .fileSizeKey ])
        else { return 0 }

        var total: Int64 = 0

        for case let url as URL in walk {
            total += Int64((try? url.resourceValues(forKeys: [ .fileSizeKey ]).fileSize) ?? 0)
        }

        return total
    }
}
