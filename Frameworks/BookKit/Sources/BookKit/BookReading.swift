//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

/// What this build makes of a book's own file.
///
/// A chapter's text is whatever a parser made of the file at the time it was read, so a parser that has
/// since learned something cannot reach the books already on the shelf: re-measuring a chapter sets the
/// words it holds again, and cannot add words it never held. The file is the only way back.
///
/// Raise this whenever a change puts something different into a chapter's stored text, and every book
/// read by an older build is read again from the file kept for exactly that. Changes to how text is set
/// rather than to what it holds belong in `Typography.version` and `ChapterLayout.rulesVersion`, which
/// re-measure without reading anything again.
public enum BookReading {
    public static let version = 6
}
