//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// The chapter bodies this device holds. The reader reads from here before it asks anything else.
public protocol ChapterBodyStore: Sendable {
    func body(workId: Int, chapterId: Int) async -> ChapterBody?

    func hasBody(workId: Int, chapterId: Int) async -> Bool

    func storedBodyIds(workId: Int) async -> Set<Int>

    func store(body: ChapterBody, workId: Int) async
}

/// Chapter text the typesetter has already been through, filed against the hashes that say whether it
/// is still the text the reader was given.
public protocol PreparedChapterStore: Sendable {
    func contentHash(workId: Int, chapterId: Int) async -> String?

    func preparedChapter(workId: Int, chapterId: Int, contentHash: String) async -> PreparedChapter?

    func store(prepared: PreparedChapter, workId: Int) async
}

/// Where each chapter sat when the book was last measured, against the book's shape and the setting.
public protocol PlacementStore: Sendable {
    func placement(workId: Int, chapterId: Int, chain: String, style: String) async -> ChapterPlacement?

    func store(placement: ChapterPlacement, workId: Int, chapterId: Int, chain: String, style: String) async
}

/// Where a book's pictures are on this device.
public protocol PictureLibrary: Sendable {
    /// The file an `<img src>` in a stored chapter body points at, or `nil` where nothing here answers
    /// to it. A picture from the service is one of those: its bytes are not on the device.
    func url(forPicture source: String) -> URL?
}
