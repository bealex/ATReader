//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// A heading parted into what it numbers and what it names.
///
/// "Глава 17 Край солёных озёр" is one string in the file and two things on the page: the chapter's
/// place, set small above, and the chapter's name, set large under it. Telling the one from the other
/// is what lets them be set apart at all.
///
/// A heading that is only a number, or only a name, is left whole. So is one where parting it would be
/// a guess: "Часть тела" opens with a word this knows, and is not a part of anything.
enum HeadingNumbering {
    /// The numbering a heading opens with and the name that follows it, where it carries both.
    static func part(_ heading: String) -> (number: String, name: String)? {
        let words = words(of: heading)

        guard let first = words.first else { return nil }

        var taken = 0

        if isPartWord(first.text) { taken = 1 }

        taken = numbered(words, from: taken)

        guard taken > 0 else { return nil }

        let numbering = heading[heading.startIndex ..< words[taken - 1].end]
        var rest = heading[words[taken - 1].end...]
        // A separator is what makes a name out of what follows: without one, only a number tells the
        // reader that the rest is a name rather than the rest of the heading.
        var parted = numbering.last.map(isSeparator) ?? false

        while let next = rest.first, next.isWhitespace || isSeparator(next) {
            parted = parted || isSeparator(next)
            rest = rest.dropFirst()
        }

        let name = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        let number =
            numbering
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".:;,—–-)|"))

        guard !name.isEmpty, !number.isEmpty, parted || taken > 1 else { return nil }

        return (number, name)
    }

    /// How many words of the heading its numbering covers, counting from whatever the part word left.
    ///
    /// A figure or a roman numeral stands alone. A numeral in words has to be an ordinal, since that is
    /// what a heading numbers itself with and a cardinal is what a title is named with: "Глава Три
    /// товарища" is a chapter called after the three, not the third chapter. English counts either way,
    /// "Chapter One" being how English books say it.
    private static func numbered(_ words: [Word], from start: Int) -> Int {
        guard start < words.count else { return start }

        let word = words[start].text

        if isFigure(word) || isRoman(word) { return start + 1 }

        // "двадцать первая": the tens stand in front of the ordinal rather than instead of it, and are
        // asked about first, since the stem an ordinal is known by answers for the round number too.
        if isTens(word), start + 1 < words.count, isOrdinal(words[start + 1].text) { return start + 2 }

        if isOrdinal(word) { return start + 1 }

        return start
    }

    // MARK: - What a word is

    private struct Word {
        /// Lowercased, with whatever punctuation it carried taken off.
        let text: String
        /// Where the word ends in the heading, punctuation included.
        let end: String.Index
    }

    private static func words(of heading: String) -> [Word] {
        var words: [Word] = []
        var index = heading.startIndex

        while index < heading.endIndex {
            while index < heading.endIndex, heading[index].isWhitespace { index = heading.index(after: index) }

            let start = index

            while index < heading.endIndex, !heading[index].isWhitespace { index = heading.index(after: index) }

            guard start < index else { break }

            words.append(Word(
                text: heading[start ..< index]
                    .lowercased()
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".:;,!?—–-()[]|«»\"'")),
                end: index
            ))
        }

        return words
    }

    private static func isSeparator(_ character: Character) -> Bool { ".:;—–-|)".contains(character) }

    private static func isFigure(_ word: String) -> Bool {
        !word.isEmpty && word.allSatisfy(\.isNumber)
    }

    /// Roman numerals proper, rather than any word spelled out of their letters: "civil" is not four.
    private static func isRoman(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }

        return word.wholeMatch(of: /m{0,3}(cm|cd|d?c{0,3})(xc|xl|l?x{0,3})(ix|iv|v?i{0,3})/) != nil
    }

    private static func isPartWord(_ word: String) -> Bool { partWords.contains(word) }

    private static func isTens(_ word: String) -> Bool { tens.contains(word) }

    /// True for a numeral in words that counts which one this is rather than how many there are.
    private static func isOrdinal(_ word: String) -> Bool {
        if english.contains(word) { return true }

        // Russian ordinals decline, and every ending they take is short, so the stem is what is
        // matched and the rest is whatever the case and gender asked for.
        return russian.contains { word.hasPrefix($0) && word.count - $0.count <= 3 }
    }

    private static let partWords: Set<String> = [
        "глава", "часть", "том", "книга", "раздел", "пролог", "эпилог", "интерлюдия", "интермедия", "действие",
        "акт", "сцена", "эпизод", "приложение", "chapter", "part", "book", "volume", "section", "prologue",
        "epilogue", "interlude", "act", "scene", "episode", "appendix",
    ]

    private static let russian: [String] = [
        "перв", "втор", "трет", "четверт", "четвёрт", "пят", "шест", "седьм", "восьм", "девят", "десят",
        "одиннадцат", "двенадцат", "тринадцат", "четырнадцат", "пятнадцат", "шестнадцат", "семнадцат",
        "восемнадцат", "девятнадцат", "двадцат", "тридцат", "сороков", "пятидесят", "шестидесят", "семидесят",
        "восьмидесят", "девяност", "сот",
    ]

    private static let tens: Set<String> = [
        "двадцать", "тридцать", "сорок", "пятьдесят", "шестьдесят", "семьдесят", "восемьдесят", "девяносто",
        "сто",
    ]

    private static let english: Set<String> = [
        "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth", "eleventh",
        "twelfth", "thirteenth", "fourteenth", "fifteenth", "sixteenth", "seventeenth", "eighteenth",
        "nineteenth", "twentieth", "thirtieth", "fortieth", "fiftieth", "one", "two", "three", "four", "five",
        "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
        "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty", "fifty",
    ]
}
