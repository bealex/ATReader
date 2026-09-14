//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// A stretch of a chapter the reader marked, as character offsets so it survives a change of font.
///
/// A page rather than a point: what the reader marks is what they can see, and a page set in one face
/// is a different page set in another. Two bookmarks of the same book never begin at the same place,
/// which is what lets one be found and taken away again.
public struct Bookmark: Sendable, Equatable, Identifiable, Hashable {
    public let workId: Int
    public let chapterId: Int
    /// Where the marked stretch begins, and where it stops. The stop is one past the last character.
    public let startOffset: Int
    public let endOffset: Int
    /// The words the mark stands on, kept so it can be found again once the offsets have moved.
    ///
    /// Offsets survive a change of font, the text they count being unchanged, and they do not survive
    /// the book being read again: a parser that has learned something writes different text and
    /// everything past the change shifts. Nothing is here for a mark written before this was kept, and
    /// such a mark is still found by its offsets, exactly as it always was.
    public let text: String?
    /// Which of the places those words appear this one was, counting from zero.
    public let occurrence: Int
    public let createdAt: Date

    public var id: String { "\(chapterId).\(startOffset)" }

    public init(
        workId: Int,
        chapterId: Int,
        startOffset: Int,
        endOffset: Int,
        text: String? = nil,
        occurrence: Int = 0,
        createdAt: Date
    ) {
        self.workId = workId
        self.chapterId = chapterId
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.text = text
        self.occurrence = occurrence
        self.createdAt = createdAt
    }

    /// Where the mark stands in a chapter now: where its words are, rather than where its offsets once
    /// pointed. A mark with no words of its own falls back to the offsets it was written with.
    public func place(in chapter: BookSearch.Folded) -> Range<Int> {
        guard
            let text,
            !text.isEmpty,
            let found = BookSearch.match(of: text, occurrence: occurrence, in: chapter)
        else {
            return startOffset ..< max(endOffset, startOffset + 1)
        }

        return found
    }

    /// True where this mark and that stretch of the same chapter share any character at all.
    ///
    /// Touching ends do not count: a mark stopping exactly where the next page starts is the page
    /// before's, or every mark would be found again from the page after it.
    public func overlaps(chapterId: Int, from start: Int, to end: Int) -> Bool {
        self.chapterId == chapterId && startOffset < max(end, start + 1) && start < max(endOffset, startOffset + 1)
    }

    /// How far into its chapter the mark begins, as `0…1`, where the chapter's length is known.
    public func share(ofChapterLength length: Int?) -> Double? {
        guard let length, length > 0 else { return nil }

        return min(1, max(0, Double(startOffset) / Double(length)))
    }
}
