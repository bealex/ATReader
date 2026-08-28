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
    /// Bumped whenever a rule here changes what a chapter's prepared text comes out as.
    ///
    /// Prepared text is kept against a hash of the chapter's source, so a chapter whose source hasn't
    /// moved is never set again. A change to these rules moves the output without moving the source,
    /// and nothing in the source would ever say so. This is what tells the store that everything it
    /// holds was made by an older typesetter and has to be made again.
    static let version = "2"

    /// A space that cannot be broken at, and that still stretches when a line is justified.
    ///
    /// A no-break space would be simpler, but it is rigid: justification cannot take it up, so the slack
    /// piles into the ordinary spaces around it and then into the gaps between letters. It is a
    /// different width from an ordinary space in most book faces too, which shows even ragged-right. An
    /// ordinary space followed by a word joiner reads as one elastic space that no line may break at.
    static let boundSpace = " \u{2060}"
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
            result += binds ? boundSpace : " "
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
        // dialogue, and the layout holds the gap after it rather than the text.
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
    /// Puts the right dash in, given the language the text is written in.
    ///
    /// Files write dashes with whatever key was to hand, and one publisher's habit runs through every
    /// book it sets. Russian puts тире between words and at the head of a line of speech, and a hyphen
    /// only inside a word, so a spaced en dash or a spaced hyphen is the wrong mark outright. English
    /// keeps the spaced en dash as a convention of its own and is left alone there, but wants an en
    /// dash between figures where a hyphen is usually typed.
    ///
    /// Every replacement is one character for one. A reading position is an offset into this text, so a
    /// substitution that changed its length would move the reader's place in every book on the device.
    /// That rules out folding `--` into an em dash, which is the one common repair this doesn't make.
    static func dashes(_ text: String, language: String?) -> String {
        guard text.contains(where: isDashLike) else { return text }

        let russian = isRussian(language)
        let characters = Array(text)
        var result = ""
        result.reserveCapacity(characters.count)

        for (index, character) in characters.enumerated() {
            guard
                isDashLike(character)
            else {
                result.append(character)
                continue
            }

            result.append(dash(
                character,
                before: index > 0 ? characters[index - 1] : nil,
                after: index + 1 < characters.count ? characters[index + 1] : nil,
                russian: russian
            ))
        }

        return result
    }

    private static func isDashLike(_ character: Character) -> Bool {
        character == "-" || character == "–" || character == "—" || character == "―"
    }

    /// The mark this dash should be, from what stands either side of it.
    ///
    /// A dash inside a word is a hyphen doing its job and is never touched: Russian is full of them,
    /// and a book of `кто-то` rewritten with тире would be unreadable.
    private static func dash(
        _ character: Character,
        before: Character?,
        after: Character?,
        russian: Bool
    ) -> Character {
        if before?.isLetter == true, after?.isLetter == true { return character }

        // A range between figures, which both traditions set with an en dash.
        if before?.isNumber == true, after?.isNumber == true { return "–" }

        // The dash opening a line of speech, at the head of a paragraph or of a line inside one.
        if before == nil || before == "\n" {
            return russian && after?.isWhitespace == true ? "—" : character
        }

        guard before?.isWhitespace == true, after?.isWhitespace == true else { return character }

        // Russian has one spaced dash and this is it. English keeps the spaced en dash it means, and
        // only a spaced hyphen is promoted to one.
        return russian ? "—" : (character == "-" ? "–" : character)
    }

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
