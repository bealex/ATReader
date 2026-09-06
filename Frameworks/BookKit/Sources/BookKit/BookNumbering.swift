//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

/// How a book that came from a file is numbered.
///
/// The service counts works up from one, so these count down from below zero and the two can never
/// collide. Ask before calling a service about a book: a book from a file has its text on the device
/// and nowhere else, and there is nothing on the other end to answer.
public enum BookNumbering {
    /// Ids a single book's chapters are taken from. A book at `-1_000_000` numbers its chapters
    /// `-1_000_001` upwards, so the chapter table's primary key stays unique across the whole library.
    private static let block = 1_000_000

    public static func isLocal(_ workId: Int) -> Bool { workId < 0 }

    /// The work id for the nth book imported on this device, counting from one.
    public static func workId(sequence: Int) -> Int { -sequence * block }

    public static func sequence(workId: Int) -> Int { -workId / block }

    /// The id of a chapter at `index` within a local book, counting from zero.
    public static func chapterId(workId: Int, index: Int) -> Int { workId - index - 1 }
}
