//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookStorage
import Foundation
import Synchronization
import Testing

/// A backup read back over a device that already holds books of its own.
struct LibraryArchiveTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    private var backup: URL { root.appendingPathComponent("backup") }
    private var books: URL { root.appendingPathComponent("Books") }

    private func store() -> SQLiteBookStore { SQLiteBookStore(fileURL: root.appendingPathComponent("library.sqlite")) }

    @Test
    func restoringPutsTheBackedUpBooksInPlaceOfTheDevicesOwn() async throws {
        defer { try? FileManager.default.removeItem(at: root) }

        let store = store()

        try write("backed up", to: "kept.fb2")
        _ = await store.books()
        let written = try await LibraryArchive.write(to: backup, store: store, books: books)

        #expect(written.files?["Books/kept.fb2"] != nil, "the backup recorded no hash for its book")
        #expect(written.files?["library.sqlite"] != nil, "the backup recorded no hash for its library")

        try FileManager.default.removeItem(at: books.appendingPathComponent("kept.fb2"))
        try write("since", to: "since.fb2")

        var shares: [Double] = []
        let told = Told()

        try await LibraryArchive.read(from: backup, store: store, books: books) { told.add($0) }
        shares = told.all

        #expect(try FileManager.default.contentsOfDirectory(atPath: books.path) == [ "kept.fb2" ])
        #expect(try String(contentsOf: books.appendingPathComponent("kept.fb2"), encoding: .utf8) == "backed up")
        #expect(shares.last == 1, "the restore never said it was done")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Books-restoring").path))
    }

    /// Same name, same size, same date, different words: only the hash tells them apart.
    @Test
    func aFileTheDeviceHoldsDifferentlyIsPutBack() async throws {
        defer { try? FileManager.default.removeItem(at: root) }

        let store = store()
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        try write("AAAA", to: "book.fb2", dated: date)
        _ = await store.books()
        try await LibraryArchive.write(to: backup, store: store, books: books)
        try write("BBBB", to: "book.fb2", dated: date)

        try await LibraryArchive.read(from: backup, store: store, books: books)

        #expect(try String(contentsOf: books.appendingPathComponent("book.fb2"), encoding: .utf8) == "AAAA")
    }

    /// A backup whose file no longer matches its record is refused, and the device keeps what it had.
    @Test
    func aDamagedBackupLeavesTheDeviceAlone() async throws {
        defer { try? FileManager.default.removeItem(at: root) }

        let store = store()

        try write("whole", to: "book.fb2")
        _ = await store.books()
        try await LibraryArchive.write(to: backup, store: store, books: books)
        try Data("broken".utf8).write(to: LibraryArchive.home(in: backup).appendingPathComponent("Books/book.fb2"))
        try write("mine", to: "book.fb2")

        await #expect(throws: ArchiveError.self) {
            try await LibraryArchive.read(from: backup, store: store, books: books)
        }
        #expect(try String(contentsOf: books.appendingPathComponent("book.fb2"), encoding: .utf8) == "mine")
    }

    private func write(_ text: String, to name: String, dated date: Date? = nil) throws {
        let file = books.appendingPathComponent(name)

        try FileManager.default.createDirectory(at: books, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)

        if let date { try FileManager.default.setAttributes([ .modificationDate: date ], ofItemAtPath: file.path) }
    }
}

/// The shares a restore told, in the order it told them.
private final class Told: Sendable {
    private let shares = Mutex<[Double]>([])

    var all: [Double] { shares.withLock { $0 } }

    func add(_ share: Double) { shares.withLock { $0.append(share) } }
}
