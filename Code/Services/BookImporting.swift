//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookFormats
import BookKit
import BookStorage
import Foundation

/// Reads a file with whichever format can, and puts what comes back on the device.
///
/// The one place the two halves meet: `BookFormats` knows how to read a book and nothing about where
/// it goes, `BookStorage` knows where it goes and nothing about how it was read.
enum BookImporting {
    /// Every format the app can read a book out of. One today; the protocol is what lets a second
    /// arrive without anything here changing.
    static let formats: [any BookFormat] = [ FB2Format() ]

    /// Reads a picked file into the library.
    ///
    /// The scope has to be held across the read and given back afterwards, or the URL stops working.
    @discardableResult
    static func `import`(from url: URL, store: SQLiteBookStore = .shared) async throws -> Book {
        let scoped = url.startAccessingSecurityScopedResource()

        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        guard let data = try? Data(contentsOf: url) else { throw FB2Error.unreadable }

        return try await install(data, store: store)
    }

    /// Reads a book this device already holds again, for one imported before the parser learned
    /// something it now knows. The file is kept for exactly this.
    @discardableResult
    static func reimport(workId: Int, store: SQLiteBookStore = .shared) async throws -> Book {
        guard let data = LocalBookFiles.keptFile(workId: workId) else { throw FB2Error.unreadable }

        // The text is already on the device by definition, so the check that stops a book arriving
        // twice would stop this book being read again at all.
        return try await install(data, store: store, deduplicating: false)
    }

    /// Reads bytes into a book without putting it anywhere.
    ///
    /// Apart from installing, so a caller that has to decide something about a book before keeping it
    /// can look at it first: whether it is already here under another name, say.
    static func read(_ data: Data) async throws -> ReadBook {
        guard let format = formats.first(where: { $0.canRead(data) }) else { throw FB2Error.notABook }

        return try await format.read(data)
    }

    @discardableResult
    static func install(
        _ read: ReadBook,
        origin: BookOrigin,
        store: SQLiteBookStore = .shared
    ) async -> Book {
        await BookInstaller.install(read.book, source: read.source, origin: origin, store: store)
    }

    private static func install(
        _ data: Data,
        store: SQLiteBookStore,
        deduplicating: Bool = true
    ) async throws -> Book {
        let read = try await read(data)

        // The same text already here, whatever file carried it in or which service it came from: one
        // book, rather than two rows of one book standing next to each other on the shelf.
        if deduplicating,
                let held = await store.localBook(contentHash: BookInstaller.hash(read.source)),
                let already = await store.book(id: held.workId) {
            return already.summary
        }

        // `data` is the file as it was picked, which is the archive where the book came in one. Kept
        // so a book bought from a service and also carried in by hand is recognised as the one book
        // it is, whichever of the two arrived first.
        return await install(
            read,
            origin: BookOrigin(source: .file, archive: data == read.source ? nil : data),
            store: store
        )
    }
}
