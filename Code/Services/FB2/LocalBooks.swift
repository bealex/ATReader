//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

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

    /// Where a book's file is kept once it has been imported.
    ///
    /// The picker hands over a URL that stops working the moment its security scope is given up, so the
    /// file is copied in and read from here afterwards.
    static var directory: URL {
        let base =
            FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Books", isDirectory: true)

        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func coverURL(workId: Int) -> URL {
        directory.appendingPathComponent("\(-workId).cover", conformingTo: .jpeg)
    }
}
