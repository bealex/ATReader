//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// Markdown's inline markup read into the chapter vocabulary: `<em>`, `<strong>`, `<br>`, a link into the
/// book, a note's marker and a picture the document carries itself.
struct MarkdownInline {
    /// Footnote labels the document defines, which is what makes `[^label]` a marker.
    let footnotes: Set<String>
    /// Every place in the document a link may land on.
    let anchors: Set<String>
    /// Pictures written into the document as `data:` addresses, by the name the markup gives them.
    private(set) var pictures: [String: Data] = [:]

    init(footnotes: Set<String>, anchors: Set<String>) {
        self.footnotes = footnotes
        self.anchors = anchors
    }

    /// What a footnote's words are filed under in a chapter body.
    static func noteId(_ label: String) -> String { "fn-\(label)" }

    mutating func html(_ source: String) -> String {
        render(tokens(Array(Self.breakingLines(source))))
    }

    /// A line ending in two spaces or a backslash breaks there; any other line break is a space.
    private static func breakingLines(_ source: String) -> String {
        source
            .replacingOccurrences(of: "( {2,}|\\\\)\n", with: String(hardBreak), options: .regularExpression)
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static let hardBreak: Character = "\u{E0FF}"

    // MARK: - Tokens

    private struct Delimiter {
        var character: Character
        var count: Int
        var canOpen: Bool
        var canClose: Bool
        /// Tags this run opens once matched, outermost first.
        var opens: [String] = []
        /// Tags this run closes once matched, innermost first.
        var closes: [String] = []
    }

    private enum Token {
        case html(String)
        case delimiter(Delimiter)
    }

    /// What a stretch of the source reads as.
    private enum Piece {
        case text(String)
        /// Markup of its own, which ends the text before it. Empty for a tag that is dropped.
        case html(String)
        case delimiter(Delimiter)
    }

    private mutating func tokens(_ characters: [Character]) -> [Token] {
        var tokens: [Token] = []
        var text = ""
        var index = 0

        while index < characters.count {
            let (piece, end) = piece(characters, at: index)

            index = end

            if case let .text(more) = piece {
                text += more
                continue
            }

            if !text.isEmpty { tokens.append(.html(text)) }

            text = ""

            switch piece {
                case let .html(html) where !html.isEmpty: tokens.append(.html(html))
                case let .delimiter(run): tokens.append(.delimiter(run))
                default: break
            }
        }

        if !text.isEmpty { tokens.append(.html(text)) }

        return tokens
    }

    /// The piece of the source opening at `index`, and where it ends.
    private mutating func piece(_ characters: [Character], at index: Int) -> (Piece, Int) {
        let character = characters[index]
        let next = index + 1 < characters.count ? characters[index + 1] : nil

        switch character {
            case Self.hardBreak:
                return (.html("<br>"), index + 1)
            case "\\" where next.map(Self.isPunctuation) ?? false:
                return (.text(Self.escaped(String(next ?? " "))), index + 2)
            case "`":
                return codeSpan(characters, at: index)
            case "[",
                "!" where next == "[":
                let isPicture = character == "!"
                let found = link(characters, at: isPicture ? index + 1 : index, isPicture: isPicture)

                return found.map { (.html($0.html), $0.end) } ?? (.text(String(character)), index + 1)
            case "<":
                let (html, end) = tag(characters, at: index)

                return (html.map(Piece.html) ?? .text("&lt;"), end)
            case "&":
                let (decoded, end) = entity(characters, at: index)

                return (.text(decoded), end)
            case "*", "_", "~":
                return run(of: character, in: characters, at: index)
            default:
                return (.text(Self.escaped(String(character))), index + 1)
        }
    }

    /// A run of emphasis marks, and whether it may open a stretch, close one, or both.
    private func run(of character: Character, in characters: [Character], at index: Int) -> (Piece, Int) {
        var count = 1

        while index + count < characters.count, characters[index + count] == character { count += 1 }

        let end = index + count

        guard character != "~" || count == 2 else { return (.text(String(repeating: "~", count: count)), end) }

        let before = index > 0 ? characters[index - 1] : " "
        let after = end < characters.count ? characters[end] : " "
        // An underscore inside a word is part of it: snake_case stays as written.
        let inWord = character == "_"
        let canOpen = Self.leans(after, awayFrom: before) && !(inWord && (before.isLetter || before.isNumber))
        let canClose = Self.leans(before, awayFrom: after) && !(inWord && (after.isLetter || after.isNumber))

        return (
            .delimiter(Delimiter(character: character, count: count, canOpen: canOpen, canClose: canClose)),
            end
        )
    }

    /// True where a run of marks leans against `inner` rather than against `outer`, which is what lets
    /// it open (or close) a stretch.
    private static func leans(_ inner: Character, awayFrom outer: Character) -> Bool {
        !inner.isWhitespace && !(isPunctuation(inner) && !outer.isWhitespace && !isPunctuation(outer))
    }

    /// A run of backticks and everything to the matching run, set as it was written.
    private func codeSpan(_ characters: [Character], at index: Int) -> (Piece, Int) {
        var run = 0

        while index + run < characters.count, characters[index + run] == "`" { run += 1 }

        var cursor = index + run

        while cursor < characters.count {
            var closing = 0

            while cursor + closing < characters.count, characters[cursor + closing] == "`" { closing += 1 }

            if closing == run {
                var code = String(characters[(index + run) ..< cursor])

                if code.count > 2, code.hasPrefix(" "), code.hasSuffix(" ") {
                    code = String(code.dropFirst().dropLast())
                }

                return (.text(Self.escaped(code)), cursor + closing)
            }

            cursor += max(1, closing)
        }

        return (.text(String(repeating: "`", count: run)), index + run)
    }

    /// A link, a picture or a footnote's marker opening at a bracket, and where it ends.
    private mutating func link(
        _ characters: [Character],
        at open: Int,
        isPicture: Bool
    ) -> (html: String, end: Int)? {
        guard let close = Self.matching("]", from: open, in: characters) else { return nil }

        let label = String(characters[(open + 1) ..< close])

        if !isPicture, label.hasPrefix("^") {
            let name = String(label.dropFirst())

            guard footnotes.contains(name) else { return nil }

            return ("<a href=\"#\(Self.escaped(Self.noteId(name)))\">\(Self.escaped(name))</a>", close + 1)
        }

        var end = close + 1
        var address = ""

        let after = end < characters.count ? characters[end] : nil

        if after == "(", let shut = Self.matching(")", from: end, in: characters) {
            address =
                String(characters[(end + 1) ..< shut]).trimmed
                .split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
            address = address.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            end = shut + 1
        } else if after == "[", let shut = Self.matching("]", from: end, in: characters) {
            end = shut + 1
        }

        if isPicture { return (picture(at: address), end) }

        var inner = MarkdownInline(footnotes: footnotes, anchors: anchors)
        let words = inner.html(label)

        pictures.merge(inner.pictures) { first, _ in first }

        if address.hasPrefix("#"), anchors.contains(String(address.dropFirst())) {
            return ("<a href=\"\(Self.escaped(address))\">\(words)</a>", end)
        }

        return (words, end)
    }

    /// A picture the document carries in itself. One it only points at is somewhere this file isn't.
    private mutating func picture(at address: String) -> String {
        guard
            address.hasPrefix("data:image/"),
            let comma = address.firstIndex(of: ","),
            address[..<comma].hasSuffix(";base64"),
            let data = Data(
                base64Encoded: String(address[address.index(after: comma)...]),
                options: .ignoreUnknownCharacters
            )
        else { return "" }

        let type = address.dropFirst("data:image/".count).prefix { $0 != ";" && $0 != "+" }
        let name = "picture-\(pictures.count + 1).\(type)"

        pictures[name] = data
        return "<img src=\"\(name)\">"
    }

    /// The bracket closing the one at `open`, stepping over any nested pair and anything escaped.
    private static func matching(_ closing: Character, from open: Int, in characters: [Character]) -> Int? {
        let opening = characters[open]
        var depth = 0
        var index = open

        while index < characters.count {
            switch characters[index] {
                case "\\": index += 1
                case opening: depth += 1
                case closing:
                    depth -= 1
                    if depth == 0 { return index }
                default: break
            }

            index += 1
        }

        return nil
    }

    /// Markup written into the text. What the chapter vocabulary reads passes through, an address
    /// written in brackets comes out as its words, and every other tag is dropped. Nothing where the
    /// bracket opens no tag at all.
    private func tag(_ characters: [Character], at open: Int) -> (String?, Int) {
        guard let close = characters[open...].firstIndex(of: ">") else { return (nil, open + 1) }

        let inside = String(characters[(open + 1) ..< close])

        if inside.contains("://") || inside.hasPrefix("mailto:") { return (Self.escaped(inside), close + 1) }

        guard let match = inside.firstMatch(of: /^(\/?)([a-zA-Z][a-zA-Z0-9]*)[^<]*$/) else { return (nil, open + 1) }

        let name = match.2.lowercased()

        guard Self.passing.contains(name) else { return ("", close + 1) }

        return (name == "br" ? "<br>" : "<\(match.1)\(name)>", close + 1)
    }

    private static let passing: Set<String> = [ "br", "em", "strong", "i", "b", "sub", "sup" ]

    /// An entity decoded into the character it names, escaped again, where it names one.
    private func entity(_ characters: [Character], at start: Int) -> (String, Int) {
        let rest = String(characters[start ..< min(characters.count, start + Self.longestEntity)])

        let found = rest.range(of: Self.entityPattern, options: .regularExpression)

        guard let found else { return ("&amp;", start + 1) }

        let body = String(rest[found].dropFirst().dropLast())
        var decoded: String?

        if body.hasPrefix("#x") || body.hasPrefix("#X") {
            decoded = UInt32(body.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String($0) }
        } else if body.hasPrefix("#") {
            decoded = UInt32(body.dropFirst()).flatMap(Unicode.Scalar.init).map { String($0) }
        } else {
            decoded = Self.entities[body]
        }

        guard let decoded else { return ("&amp;", start + 1) }

        return (Self.escaped(decoded), start + rest[found].count)
    }

    private static let longestEntity = 12
    private static let entityPattern = "^&(#\\d{1,7}|#[xX][0-9a-fA-F]{1,6}|[a-zA-Z]{2,8});"

    private static let entities = [
        "nbsp": "\u{00A0}", "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "copy": "©",
        "mdash": "—", "ndash": "–", "hellip": "…", "laquo": "«", "raquo": "»", "shy": "\u{00AD}",
    ]

    // MARK: - Emphasis

    /// Pairs every closing run of marks with the nearest opening one of the same kind, and writes
    /// out what they enclose.
    private func render(_ tokens: [Token]) -> String {
        var tokens = tokens

        for closer in tokens.indices {
            guard case let .delimiter(closing) = tokens[closer], closing.canClose else { continue }

            tokens[closer] = .delimiter(Self.pair(closing, at: closer, in: &tokens))
        }

        return tokens.map { token in
            switch token {
                case let .html(html): html
                case let .delimiter(run):
                    run.closes.joined() + String(repeating: run.character, count: run.count) + run.opens.joined()
            }
        }.joined()
    }

    /// Matches one closing run against the opening runs before it, nearest first, for as long as it
    /// has marks left.
    private static func pair(_ closing: Delimiter, at closer: Int, in tokens: inout [Token]) -> Delimiter {
        var closing = closing
        var opener = closer - 1

        while opener >= 0, closing.count > 0 {
            guard
                case var .delimiter(opening) = tokens[opener],
                opening.character == closing.character,
                opening.canOpen,
                opening.count > 0
            else {
                opener -= 1
                continue
            }

            let used = opening.count >= 2 && closing.count >= 2 ? 2 : 1

            guard closing.character != "~" || used == 2 else { break }

            let name = closing.character == "~" ? "" : used == 2 ? "strong" : "em"

            if !name.isEmpty {
                opening.opens.insert("<\(name)>", at: 0)
                closing.closes.append("</\(name)>")
            }

            opening.count -= used
            closing.count -= used
            tokens[opener] = .delimiter(opening)

            // Marks left open between the two can no longer close anything outside them.
            for between in (opener + 1) ..< closer {
                if case var .delimiter(inside) = tokens[between], inside.count > 0 {
                    inside.canOpen = false
                    tokens[between] = .delimiter(inside)
                }
            }

            if opening.count > 0 { continue }

            opener -= 1
        }

        return closing
    }

    // MARK: - Characters

    static func escaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func isPunctuation(_ character: Character) -> Bool {
        character.isPunctuation || character.isSymbol
    }
}
