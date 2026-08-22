//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// The line-breaking rules a typesetter follows but a layout engine doesn't know about.
///
/// TextKit breaks a line at any space it likes. Both traditions forbid some of those breaks, and they
/// forbid different ones: Russian will not let a line end on a one- or two-letter preposition, nor begin
/// with a dash; English is easier on short words but keeps an abbreviation with the name it belongs to.
/// The way to say so is a no-break space, put in before the text is laid out.
enum Typography {
    static let noBreakSpace = "\u{00A0}"
    /// Invisible until a line breaks there, where the layout draws a hyphen.
    static let softHyphen: Character = "\u{00AD}"

    /// Words shorter than this are left whole: breaking a five-letter word saves nothing and reads badly.
    private static let shortestHyphenatedWord = 6
    /// Letters kept either side of a break. Two is the tightest either tradition allows.
    private static let hyphenationEdge = 2

    /// Whether a language tag from the chapter names Russian, which several rules turn on.
    static func isRussian(_ language: String?) -> Bool { language?.hasPrefix("ru") ?? false }

    /// Binds the words that must not be parted, in whichever language the text is written.
    static func bound(_ text: String, language: String?) -> String {
        guard text.contains(" ") else { return text }

        let russian = isRussian(language)
        let tokens = text.components(separatedBy: " ")

        guard tokens.count > 1 else { return text }

        var result = tokens[0]

        for index in 1 ..< tokens.count {
            let previous = tokens[index - 1]
            let next = tokens[index]
            let binds = binds(previous, to: next, russian: russian)
            result += binds ? noBreakSpace : " "
            result += next
        }

        return result
    }

    private static func binds(_ previous: String, to next: String, russian: Bool) -> Bool {
        let left = previous.trimmingCharacters(in: openingMarks)
        let right = next

        // A pair held together still has to fit on a line.
        guard left.count + right.count < 24, !left.isEmpty, !right.isEmpty else { return false }

        // A dash may not open a line; it stays with the words before it. A dash opening a paragraph is
        // dialogue and never reaches here, since nothing precedes it.
        if dashes.contains(right) { return true }

        // Nor may a line end on a lone piece of punctuation.
        if right.rangeOfCharacter(from: .alphanumerics) == nil, right.count <= 2 { return true }

        if isNumber(left), right.count <= 3 || right.first.map({ units.contains($0) }) == true { return true }
        if left.hasSuffix("№") || left.hasSuffix("§") { return true }
        // An initial belongs to the name it stands before.
        if left.count == 2, left.hasSuffix("."), left.first?.isLetter == true { return true }

        guard russian else { return englishBinds(left) }

        // The Russian rule proper: a short preposition, conjunction or particle never ends a line.
        return left.count <= 2 && left.allSatisfy(\.isLetter)
    }

    private static func englishBinds(_ left: String) -> Bool {
        abbreviations.contains(left.lowercased())
    }

    private static func isNumber(_ token: String) -> Bool {
        !token.isEmpty && token.allSatisfy { $0.isNumber || $0 == "," || $0 == "." || $0 == "–" || $0 == "-" }
    }

    private static let dashes: Set<String> = [ "—", "–", "-", "―" ]
    private static let units: Set<Character> = [ "%", "°", "€", "$", "×" ]
    private static let openingMarks = CharacterSet(charactersIn: "«„“\"'([{")
    private static let abbreviations: Set<String> = [
        "mr.", "mrs.", "ms.", "dr.", "prof.", "st.", "no.", "fig.", "vol.", "ch.", "p.", "pp.", "ed.",
    ]
}

extension Typography {
    /// Marks every place the language's own dictionary allows a word to break.
    ///
    /// TextKit looks for its own break points and settles for far fewer than the dictionary offers, so a
    /// narrow justified column ends up with lines it stretches instead of lines it breaks. A soft hyphen
    /// is a break it always sees, and one it draws a hyphen at.
    static func hyphenated(_ text: String, language: String?) -> String {
        guard let locale = hyphenationLocale(language), !text.isEmpty else { return text }

        var result = ""
        result.reserveCapacity(text.count + text.count / 6)
        var word = ""

        for character in text {
            guard
                character.isLetter
            else {
                result += hyphenate(word, locale: locale)
                result.append(character)
                word = ""
                continue
            }

            word.append(character)
        }

        return result + hyphenate(word, locale: locale)
    }

    /// The dictionary to break with, or `nil` when the system ships none for this language.
    private static func hyphenationLocale(_ language: String?) -> Locale? {
        guard let language else { return nil }

        let locale = Locale(identifier: language)
        return CFStringIsHyphenationAvailableForLocale(locale as CFLocale) ? locale : nil
    }

    /// Walks a word from its end, asking for the break before each one found, so every position the
    /// dictionary knows is marked. Positions are UTF-16 offsets, which is why this works on `NSString`.
    private static func hyphenate(_ word: String, locale: Locale) -> String {
        guard word.count >= shortestHyphenatedWord else { return word }

        let text = word as CFString
        let length = CFStringGetLength(text)
        let whole = CFRange(location: 0, length: length)
        let result = NSMutableString(string: word)
        var index = length - hyphenationEdge

        while index > hyphenationEdge {
            let position = CFStringGetHyphenationLocationBeforeIndex(text, index, whole, 0, locale as CFLocale, nil)

            guard
                position != kCFNotFound,
                position >= hyphenationEdge,
                position <= length - hyphenationEdge
            else { break }

            result.insert(String(softHyphen), at: position)
            index = position
        }

        return result as String
    }
}
