//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// Finding a passage again by the words in it, whatever has happened to the text around them.
///
/// A reading position is an offset, and an offset survives a change of font because the text it counts
/// is unchanged. It does not survive the book being read again: a parser that has learned something
/// writes different text, and everything past the change moves. Words do not move, so a mark that
/// knows its own words can always be found again.
///
/// The search is over the letters and figures alone. Case, spaces and punctuation are dropped, which is
/// what lets a passage be found after it has been re-spaced, re-punctuated, or set with a different
/// dash than the one it was marked with.
public enum BookSearch {
    /// A stretch of text folded for searching, with the way back to where every kept character stood.
    ///
    /// Folded once and searched many times, since folding a chapter costs a pass over all of it and a
    /// book asks the same chapter about several marks.
    public struct Folded: Sendable, Equatable {
        /// The letters and figures, lowercased, with everything else taken out.
        public let letters: [Character]
        /// Where each of them began in the text it was folded from, counted the way every other offset
        /// in the app is.
        let starts: [Int]
        /// Where each of them ended, which is one past its last unit.
        let ends: [Int]

        public var isEmpty: Bool { letters.isEmpty }
    }

    /// Folds a stretch of text, keeping the way back to it.
    ///
    /// A character that lowercases into more than one keeps the place of the character it came from,
    /// so every folded character can be pointed back at the text it was folded from.
    public static func fold(_ text: String) -> Folded {
        var letters: [Character] = []
        var starts: [Int] = []
        var ends: [Int] = []
        var place = 0

        for character in text {
            let width = character.utf16.count

            defer { place += width }

            guard character.isLetter || character.isNumber else { continue }

            for folded in character.lowercased() {
                letters.append(folded)
                starts.append(place)
                ends.append(place + width)
            }
        }

        return Folded(letters: letters, starts: starts, ends: ends)
    }

    /// Every place the words appear, as stretches of the text they were folded from.
    public static func matches(of words: String, in text: Folded) -> [Range<Int>] {
        let needle = fold(words).letters

        guard !needle.isEmpty, needle.count <= text.letters.count else { return [] }

        var found: [Range<Int>] = []
        var at = 0

        while at <= text.letters.count - needle.count {
            guard
                text.letters[at] == needle[0],
                Array(text.letters[at ..< at + needle.count]) == needle
            else {
                at += 1
                continue
            }

            found.append(text.starts[at] ..< text.ends[at + needle.count - 1])
            // Matches never overlap, so the next one starts after this one ends.
            at += needle.count
        }

        return found
    }

    public static func matches(of words: String, in text: String) -> [Range<Int>] {
        matches(of: words, in: fold(text))
    }

    /// One of those places, counting from zero, or nothing where the words have moved or gone.
    ///
    /// A passage marked once may read the same as another elsewhere in the chapter, so which one it was
    /// is kept with it. Where the count no longer reaches, the first is taken: a book edited since is
    /// better opened near the mark than not at all.
    public static func match(of words: String, occurrence: Int, in text: Folded) -> Range<Int>? {
        let found = matches(of: words, in: text)

        guard !found.isEmpty else { return nil }

        return found.indices.contains(occurrence) ? found[occurrence] : found[0]
    }

    /// Which of the places a stretch of the text is, for a mark being written down.
    ///
    /// The one at or after where the stretch was taken from. A match begins at its first letter, and
    /// the stretch usually begins on the space or the dash before that, so the two rarely meet exactly.
    public static func occurrence(of words: String, at start: Int, in text: Folded) -> Int {
        matches(of: words, in: text).firstIndex { $0.lowerBound >= start } ?? 0
    }
}
