//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Foundation
import UniformTypeIdentifiers

/// Reading a book out of an FB2 file, zipped or not.
public struct FB2Format: BookFormat {
    public init() {}

    /// What a picker offers when it is asking for a book of this format.
    public static var contentTypes: [UTType] {
        [ UTType(filenameExtension: "fb2"), .xml, .zip ].compactMap { $0 }
    }

    public func canRead(_ data: Data) -> Bool {
        ZipArchive.isArchive(data) || FB2Parser.looksLikeFB2(data)
    }

    /// A book handed over zipped is the common case, so the archive is opened here rather than the
    /// reader being asked to unpack it first.
    public func read(_ data: Data) async throws -> ReadBook {
        let unpacked = try await unpacked(data)
        let book = try await Task.detached(priority: .userInitiated) {
            try FB2Parser.parse(unpacked)
        }.value

        // The unpacked book rather than the archive: what is kept is what a parser reads again.
        return ReadBook(book: book, source: unpacked)
    }

    /// The book inside the file, which is the file itself unless it is an archive.
    ///
    /// The bytes decide rather than the name: these arrive called `.fb2.zip`, `.zip` and occasionally
    /// `.fb2` while being an archive all the same.
    private func unpacked(_ data: Data) async throws -> Data {
        guard ZipArchive.isArchive(data) else { return data }

        return try await Task.detached(priority: .userInitiated) {
            try ZipArchive.book(in: data)
        }.value
    }
}
