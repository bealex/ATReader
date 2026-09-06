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

        return try await install(data, store: store)
    }

    private static func install(_ data: Data, store: SQLiteBookStore) async throws -> Book {
        guard let format = formats.first(where: { $0.canRead(data) }) else { throw FB2Error.notABook }

        let read = try await format.read(data)
        return await BookInstaller.install(read.book, source: read.source, store: store)
    }
}
