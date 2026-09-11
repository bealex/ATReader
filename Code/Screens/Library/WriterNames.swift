//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// Which spellings of a name are one writer, found in the names a library holds.
///
/// Two services write one Russian name two ways: surname first or last, with the patronymic or without
/// it. Names that agree once their words are put in order and a patronymic is set aside are one writer.
/// Two names with different patronymics stay apart, and a name with none then joins neither, since there
/// is no telling whose it is.
enum WriterNames {
    /// The name each spelling is filed under, keyed by the spelling itself.
    ///
    ///     filed([ "Сомов Пётр Ильич", "Пётр Ильич Сомов", "Пётр Сомов" ])
    ///     // every one of them filed under whichever the library holds most books by
    static func filed(_ names: [String]) -> [String: String] {
        var counts: [String: Int] = [:]

        for name in names where !name.isEmpty { counts[name, default: 0] += 1 }

        var filed: [String: String] = [:]

        for writer in Dictionary(grouping: counts.keys, by: core).values.flatMap(split) {
            let chosen = writer.max { chosenBefore($1, $0, counts: counts) } ?? ""

            for name in writer { filed[name] = chosen }
        }

        return filed
    }

    /// One core's names as the writers they are: all of them, unless two patronymics tell people apart.
    private static func split(_ names: [String]) -> [[String]] {
        let byPatronymic = Dictionary(grouping: names) { patronymic(of: $0) ?? "" }
        let patronymics = byPatronymic.keys.filter { !$0.isEmpty }

        guard patronymics.count > 1 else { return [ names ] }

        return patronymics.compactMap { byPatronymic[$0] } + (byPatronymic[""] ?? []).map { [ $0 ] }
    }

    /// Whether `left` is the better name to file a writer under: the one with more books, then the
    /// fuller one, then the first in order.
    private static func chosenBefore(_ left: String, _ right: String, counts: [String: Int]) -> Bool {
        let (leftCount, rightCount) = (counts[left] ?? 0, counts[right] ?? 0)

        guard leftCount == rightCount else { return leftCount > rightCount }
        guard left.count == right.count else { return left.count > right.count }

        return left < right
    }

    /// A name's words in order, its patronymic set aside.
    private static func core(_ name: String) -> String {
        let words = self.words(of: name)
        let kept = patronymicIndex(in: words).map { index in
            words.enumerated().filter { $0.offset != index }.map(\.element)
        }

        return (kept ?? words).sorted().joined(separator: " ")
    }

    private static func patronymic(of name: String) -> String? {
        let words = self.words(of: name)

        return patronymicIndex(in: words).map { words[$0] }
    }

    /// Where a three-word name keeps its patronymic: second when the given name leads, third when the
    /// surname does. A name of any other length has none, since a surname can end the way one does.
    private static func patronymicIndex(in words: [String]) -> Int? {
        guard words.count == 3 else { return nil }

        return [ 1, 2 ].first { isPatronymic(words[$0]) }
    }

    private static func isPatronymic(_ word: String) -> Bool {
        word.count >= minimumPatronymic && patronymicEndings.contains { word.hasSuffix($0) }
    }

    private static let patronymicEndings = [ "вич", "вна", "ична", "ич" ]
    private static let minimumPatronymic = 5

    /// A name's words, lower-cased, with ё read as е and punctuation dropped.
    private static func words(of name: String) -> [String] {
        name.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .split { !$0.isLetter }
            .map(String.init)
    }
}
