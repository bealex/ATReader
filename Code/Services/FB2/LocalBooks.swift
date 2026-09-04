//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import UniformTypeIdentifiers

/// How a book that came from a file rather than from the service is numbered.
///
/// The service numbers its works from one upwards, so these count down from below zero and the two can
/// never collide. Every table in ``LocalStore`` is keyed on those numbers, and a screen asks
/// ``isLocal(_:)`` rather than the database whenever the only question is whether to call the service.
enum LocalBooks {
    /// Ids a single book's chapters are taken from. A book at `-1_000_000` numbers its chapters
    /// `-1_000_001` upwards, so the chapter table's primary key stays unique across the whole library.
    private static let block = 1_000_000

    static func isLocal(_ workId: Int) -> Bool { workId < 0 }

    /// The work id for the nth book imported on this device, counting from one.
    static func workId(sequence: Int) -> Int { -sequence * block }

    static func sequence(workId: Int) -> Int { -workId / block }

    /// The id of a chapter at `index` within a local book, counting from zero.
    static func chapterId(workId: Int, index: Int) -> Int { workId - index - 1 }

    /// Where everything an imported book brought with it is kept: its file, its cover and its pictures.
    static var directory: URL {
        let base =
            FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Books", isDirectory: true)

        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// What a picker offers when it is asking for a book.
    ///
    /// FB2 has no type of its own on the system, so it is named by its extension. XML is offered beside
    /// it because a file saved from a browser often arrives typed as that instead, and zip because that
    /// is how these books are usually handed out.
    static var fileTypes: [UTType] {
        [ UTType(filenameExtension: "fb2"), .xml, .zip ].compactMap { $0 }
    }

    /// Where a book's own file is kept.
    ///
    /// The picker hands over a URL that stops working the moment its security scope is given up, so the
    /// file itself is copied in. What a book holds is whatever the parser made of it at the time, and a
    /// parser that has since learned something can only be applied to the file.
    static func fileURL(workId: Int) -> URL {
        directory.appendingPathComponent("\(-workId).fb2z")
    }

    /// Keeps a book's own text, compressed. FB2 is XML around base64, and squeezing it saves about a
    /// third of a file that would otherwise sit on the device at full size for good.
    static func keep(_ book: Data, workId: Int) throws {
        try ((book as NSData).compressed(using: .zlib) as Data).write(to: fileURL(workId: workId), options: .atomic)
    }

    /// The book's own text as it was imported, where this device still has it.
    static func keptFile(workId: Int) -> Data? {
        guard
            let squeezed = try? Data(contentsOf: fileURL(workId: workId)),
            let book = try? (squeezed as NSData).decompressed(using: .zlib)
        else { return nil }

        return book as Data
    }

    /// True where the book's own text is still here, which is what lets it be read again without the
    /// reader naming the file. A book imported before it was kept has none.
    static func hasKeptFile(workId: Int) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(workId: workId).path)
    }

    static func coverURL(workId: Int) -> URL {
        directory.appendingPathComponent("\(-workId).cover", conformingTo: .jpeg)
    }

    /// Where a book's pictures are kept, one directory per book so removing the book removes them.
    static func imagesDirectory(workId: Int) -> URL {
        directory
            .appendingPathComponent("Images", isDirectory: true)
            .appendingPathComponent("\(-workId)", isDirectory: true)
    }

    /// What an `<img src>` in a stored chapter body points at.
    ///
    /// The book is named in the source rather than passed alongside it, so a chapter body carries
    /// everything needed to find its own pictures.
    static func imageSource(workId: Int, name: String) -> String { "\(-workId)/\(name)" }

    static func imageURL(source: String) -> URL? {
        let parts = source.split(separator: "/")

        guard parts.count == 2, Int(parts[0]) != nil, !parts[1].contains("..") else { return nil }

        return
            directory
            .appendingPathComponent("Images", isDirectory: true)
            .appendingPathComponent(String(parts[0]), isDirectory: true)
            .appendingPathComponent(String(parts[1]))
    }
}
