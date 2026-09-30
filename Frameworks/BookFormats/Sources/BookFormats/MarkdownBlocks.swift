//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Foundation

/// One block of a Markdown document, its inline markup still unread.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    /// A list item at a depth from one, opening with the mark it is shown with. An empty mark is a
    /// further paragraph of the item above it.
    case item(level: Int, mark: String, text: String)
    case quote([MarkdownBlock])
    case code([String])
    case rule
    case table(header: [String], alignments: [BookTable.Alignment], rows: [[String]])
    /// Markup written straight into the document that the chapter vocabulary reads as it is.
    case html(String)
}

/// A Markdown document split into blocks, with what stands beside them.
struct MarkdownDocument {
    /// The front matter's `key: value` pairs, keys lowercased.
    var metadata: [String: String] = [:]
    var blocks: [MarkdownBlock] = []
    /// Footnote definitions by their label, their inline markup unread.
    var footnotes: [String: String] = [:]

    init(_ text: String) {
        var lines =
            text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: "    ")
            .components(separatedBy: "\n")

        if lines.first?.hasPrefix("\u{FEFF}") == true { lines[0].removeFirst() }

        metadata = Self.frontMatter(&lines)

        var reader = MarkdownBlockReader()

        blocks = reader.blocks(lines[...])
        footnotes = reader.footnotes
    }

    /// Reads and removes a YAML front matter block, keeping its plain `key: value` pairs. A key given as
    /// a list keeps its items joined with commas.
    private static func frontMatter(_ lines: inout [String]) -> [String: String] {
        guard
            lines.first?.trimmed == "---",
            let end = lines.dropFirst().firstIndex(where: { $0.trimmed == "---" || $0.trimmed == "..." })
        else { return [:] }

        var result: [String: String] = [:]
        var listing: String?

        for line in lines[1 ..< end] {
            let trimmed = line.trimmed

            if let key = listing, trimmed.hasPrefix("- ") {
                let item = unquoted(String(trimmed.dropFirst(2)))

                result[key] = result[key].map { $0.isEmpty ? item : "\($0), \(item)" } ?? item
                continue
            }

            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" ") else { continue }

            let key = String(line[..<colon]).trimmed.lowercased()
            let value = unquoted(String(line[line.index(after: colon)...]).trimmed)

            result[key] = value
            listing = value.isEmpty ? key : nil
        }

        lines.removeSubrange(0 ... end)
        return result
    }

    private static func unquoted(_ value: String) -> String {
        var value = value

        if value.hasPrefix("["), value.hasSuffix("]") { value = String(value.dropFirst().dropLast()) }

        let quotes: Set<Character> = [ "\"", "'" ]

        guard
            value.count >= 2,
            let first = value.first,
            quotes.contains(first),
            value.last == first
        else { return value.trimmed }

        return String(value.dropFirst().dropLast())
    }
}

/// Reads lines into blocks, a document or the inside of a quotation at a time.
struct MarkdownBlockReader {
    private(set) var footnotes: [String: String] = [:]

    mutating func blocks(_ lines: ArraySlice<String>) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        var paragraph: [String] = []
        var index = lines.startIndex

        while index < lines.endIndex {
            let line = lines[index]

            if !paragraph.isEmpty, let level = Self.underline(line) {
                result.append(.heading(level: level, text: paragraph.joined(separator: " ")))
                paragraph = []
                index += 1
            } else if let read = opening(in: lines, at: &index, afterText: !paragraph.isEmpty) {
                if !paragraph.isEmpty { result.append(.paragraph(paragraph.joined(separator: "\n"))) }

                paragraph = []
                result.append(contentsOf: read)
            } else {
                paragraph.append(line)
                index += 1
            }
        }

        if !paragraph.isEmpty { result.append(.paragraph(paragraph.joined(separator: "\n"))) }

        return result
    }

    /// The blocks a line opens, read through to where they end, or nothing where the line runs on as
    /// the text of a paragraph.
    private mutating func opening(
        in lines: ArraySlice<String>,
        at index: inout Int,
        afterText: Bool
    ) -> [MarkdownBlock]? {
        let line = lines[index]

        if line.trimmed.isEmpty {
            index += 1
            return []
        }

        if let fence = Self.fence(line) { return [ .code(code(in: lines, from: &index, fence: fence)) ] }

        if let heading = Self.heading(line) ?? (Self.isRule(line) ? .rule : nil) {
            index += 1
            return [ heading ]
        }

        if Self.quoted(line) != nil { return [ .quote(quote(in: lines, from: &index)) ] }

        if let (label, text) = Self.footnote(line) {
            footnote(label, text, in: lines, from: &index)
            return []
        }

        if let table = table(in: lines, from: &index) { return [ table ] }

        if Self.item(line) != nil { return list(in: lines, from: &index) }

        return aside(in: lines, at: &index, afterText: afterText)
    }

    /// The rarer blocks: code set in by its indent, a comment, a table written in HTML, and a link
    /// reference, which shows nothing.
    private func aside(in lines: ArraySlice<String>, at index: inout Int, afterText: Bool) -> [MarkdownBlock]? {
        let line = lines[index]
        let trimmed = line.trimmed

        if !afterText, Self.isReference(line) {
            index += 1
            return []
        }

        if !afterText, Self.indent(of: line) >= Self.codeIndent {
            return [ .code(indentedCode(in: lines, from: &index)) ]
        }

        if trimmed.hasPrefix("<!--") {
            while index < lines.endIndex, !lines[index].contains("-->") { index += 1 }

            index += 1
            return []
        }

        if trimmed.lowercased().hasPrefix("<table") { return [ .html(rawTable(in: lines, from: &index)) ] }

        return nil
    }

    // MARK: - Recognising a line

    private static let codeIndent = 4

    static func indent(of line: some StringProtocol) -> Int { line.prefix { $0 == " " }.count }

    /// An opening code fence: its character and how long a run of it closes the block.
    private static func fence(_ line: String) -> (character: Character, length: Int)? {
        let trimmed = line.drop { $0 == " " }

        guard indent(of: line) < codeIndent, let first = trimmed.first, first == "`" || first == "~" else { return nil }

        let length = trimmed.prefix { $0 == first }.count

        guard length >= 3 else { return nil }
        guard first == "~" || !trimmed.dropFirst(length).contains("`") else { return nil }

        return (first, length)
    }

    private static func heading(_ line: String) -> MarkdownBlock? {
        guard indent(of: line) < codeIndent else { return nil }

        let trimmed = line.drop { $0 == " " }
        let level = trimmed.prefix { $0 == "#" }.count
        let rest = trimmed.dropFirst(level)

        guard (1 ... 6).contains(level), rest.isEmpty || rest.first == " " else { return nil }

        var text = String(rest).trimmed

        // A closing run of hashes is decoration, where a space stands before it.
        if let closing = text.range(of: "(^|\\s)#+$", options: .regularExpression) {
            text = String(text[..<closing.lowerBound]).trimmed
        }

        return .heading(level: level, text: text)
    }

    private static func underline(_ line: String) -> Int? {
        guard indent(of: line) < codeIndent else { return nil }

        let trimmed = line.trimmed

        if !trimmed.isEmpty, trimmed.allSatisfy({ $0 == "=" }) { return 1 }
        if !trimmed.isEmpty, trimmed.allSatisfy({ $0 == "-" }) { return 2 }

        return nil
    }

    private static func isRule(_ line: String) -> Bool {
        guard indent(of: line) < codeIndent else { return false }

        let marks = line.filter { $0 != " " }

        guard let first = marks.first, "-*_".contains(first) else { return false }

        return marks.count >= 3 && marks.allSatisfy { $0 == first }
    }

    /// The line with its quotation mark taken off, where it opens with one.
    private static func quoted(_ line: String) -> String? {
        guard indent(of: line) < codeIndent else { return nil }

        let trimmed = line.drop { $0 == " " }

        guard trimmed.first == ">" else { return nil }

        let rest = trimmed.dropFirst()

        return String(rest.first == " " ? rest.dropFirst() : rest)
    }

    private static func footnote(_ line: String) -> (String, String)? {
        guard let match = line.firstMatch(of: /^ {0,3}\[\^([^\]\s]+)\]:\s?(.*)$/) else { return nil }

        return (String(match.1), String(match.2))
    }

    /// A link reference definition, which names an address and shows nothing.
    private static func isReference(_ line: String) -> Bool {
        line.firstMatch(of: /^ {0,3}\[[^\]^][^\]]*\]:\s*\S+/) != nil
    }

    /// A list item's opening: how far in its mark stands, the mark, and where its words start.
    struct ItemOpening {
        var indent: Int
        var number: Int?
        var content: Int
        var text: String
    }

    static func item(_ line: String) -> ItemOpening? {
        guard let match = line.firstMatch(of: /^( *)([-*+]|\d{1,9}(?:\.|\)))( +|$)(.*)$/) else { return nil }

        let indent = match.1.count
        let spaces = match.3.count

        return ItemOpening(
            indent: indent,
            number: Int(match.2.dropLast()),
            content: indent + match.2.count + (spaces > codeIndent ? 1 : max(1, spaces)),
            text: String(match.4)
        )
    }

    /// The alignments a table's delimiter row gives its columns, where the line is one.
    private static func delimiters(_ line: String) -> [BookTable.Alignment]? {
        let cells = cells(of: line)

        guard !cells.isEmpty, line.contains("-") else { return nil }

        var alignments: [BookTable.Alignment] = []

        for cell in cells {
            guard cell.wholeMatch(of: /:?-+:?/) != nil else { return nil }

            let left = cell.hasPrefix(":")
            let right = cell.hasSuffix(":")

            alignments.append(left && right ? .center : right ? .trailing : .leading)
        }

        return alignments
    }

    /// A table row's cells, split at every bar that is not escaped.
    static func cells(of line: String) -> [String] {
        var trimmed = line.trimmed

        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|"), !trimmed.hasSuffix("\\|") { trimmed.removeLast() }

        var cells: [String] = []
        var current = ""
        var escaping = false

        for character in trimmed {
            if escaping {
                current.append(character == "|" ? "|" : "\\\(character)")
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else if character == "|" {
                cells.append(current.trimmed)
                current = ""
            } else {
                current.append(character)
            }
        }

        if escaping { current.append("\\") }

        cells.append(current.trimmed)
        return cells
    }

    // MARK: - Reading a block of several lines

    private func code(
        in lines: ArraySlice<String>,
        from index: inout Int,
        fence: (character: Character, length: Int)
    ) -> [String] {
        let indent = Self.indent(of: lines[index])
        var code: [String] = []

        index += 1

        while index < lines.endIndex {
            let line = lines[index]
            let trimmed = line.trimmed

            index += 1

            if trimmed.count >= fence.length, trimmed.allSatisfy({ $0 == fence.character }) { break }

            code.append(String(line.dropFirst(min(indent, Self.indent(of: line)))))
        }

        return code
    }

    private func indentedCode(in lines: ArraySlice<String>, from index: inout Int) -> [String] {
        var code: [String] = []

        while index < lines.endIndex {
            let line = lines[index]

            guard line.trimmed.isEmpty || Self.indent(of: line) >= Self.codeIndent else { break }

            code.append(String(line.dropFirst(min(Self.codeIndent, Self.indent(of: line)))))
            index += 1
        }

        while code.last?.trimmed.isEmpty == true { code.removeLast() }

        return code
    }

    /// A quotation, and the lines that run on from it lazily without a mark of their own.
    private mutating func quote(in lines: ArraySlice<String>, from index: inout Int) -> [MarkdownBlock] {
        var inner: [String] = []

        while index < lines.endIndex {
            let line = lines[index]

            if let rest = Self.quoted(line) {
                inner.append(rest)
            } else if !line.trimmed.isEmpty, !(inner.last?.trimmed.isEmpty ?? true), startsNothing(line) {
                inner.append(line)
            } else {
                break
            }

            index += 1
        }

        return blocks(inner[...])
    }

    private mutating func footnote(
        _ label: String,
        _ text: String,
        in lines: ArraySlice<String>,
        from index: inout Int
    ) {
        var body = [ text ]

        index += 1

        while index < lines.endIndex {
            let line = lines[index]

            if line.trimmed.isEmpty {
                guard index + 1 < lines.endIndex, Self.indent(of: lines[index + 1]) >= Self.codeIndent else { break }
            } else if Self.indent(of: line) < Self.codeIndent, !startsNothing(line) || Self.footnote(line) != nil {
                break
            }

            body.append(line.trimmed)
            index += 1
        }

        footnotes[label] = body.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// A pipe table, where the line opens one: a row, and under it a row of delimiters.
    private func table(in lines: ArraySlice<String>, from index: inout Int) -> MarkdownBlock? {
        guard
            index + 1 < lines.endIndex,
            lines[index].contains("|"),
            let alignments = Self.delimiters(lines[index + 1])
        else { return nil }

        let header = Self.cells(of: lines[index])
        var rows: [[String]] = []

        index += 2

        while index < lines.endIndex, !lines[index].trimmed.isEmpty, lines[index].contains("|") {
            rows.append(Self.cells(of: lines[index]))
            index += 1
        }

        return .table(header: header, alignments: alignments, rows: rows)
    }

    private func rawTable(in lines: ArraySlice<String>, from index: inout Int) -> String {
        var markup: [String] = []

        while index < lines.endIndex {
            let line = lines[index]

            markup.append(line)
            index += 1

            if line.lowercased().contains("</table>") { break }
        }

        return markup.joined(separator: "\n")
    }

    /// A list and everything nested in it, down to the first line that belongs to none of its items.
    /// One level of a list being read: where its marks stand, where its words start, and the number
    /// its latest item was given.
    private struct ListLevel {
        var indent: Int
        var content: Int
        var number: Int?
    }

    private mutating func list(in lines: ArraySlice<String>, from index: inout Int) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        var levels: [ListLevel] = []
        var text: [String] = []
        var mark = ""
        var sawBlank = false

        func flush() {
            guard !text.isEmpty || !mark.isEmpty else { return }

            result.append(.item(level: max(1, levels.count), mark: mark, text: text.joined(separator: "\n")))
            text = []
            mark = ""
        }

        while index < lines.endIndex {
            let line = lines[index]

            if line.trimmed.isEmpty {
                sawBlank = true
                index += 1
                continue
            }

            if let opening = Self.item(line), !Self.isRule(line) || opening.number != nil {
                flush()
                Self.nest(opening, in: &levels)

                let marked = Self.marked(opening.text, number: levels.last?.number)

                mark = marked.mark
                text = [ marked.text ]
                sawBlank = false
                index += 1
                continue
            }

            let indent = Self.indent(of: line)

            if sawBlank {
                guard let deepest = levels.lastIndex(where: { indent >= $0.content }) else { break }

                flush()
                levels.removeSubrange((deepest + 1)...)
                sawBlank = false
            } else if indent < (levels.last?.content ?? 0), !startsNothing(line) {
                break
            }

            let inner = String(line.dropFirst(min(indent, levels.last?.content ?? 0)))

            if let fence = Self.fence(inner) {
                flush()
                result.append(.code(code(in: lines, from: &index, fence: fence)))
                continue
            }

            text.append(inner)
            index += 1
        }

        flush()
        return result
    }

    /// Stands an item at its depth: under the item above where its mark stands inside that item's
    /// words, beside it otherwise, numbered on from the item it follows.
    private static func nest(_ opening: ItemOpening, in levels: inout [ListLevel]) {
        while let last = levels.last, opening.indent < last.indent { levels.removeLast() }

        let level = ListLevel(indent: opening.indent, content: opening.content, number: opening.number)

        guard let last = levels.last, opening.indent < last.content else { return levels.append(level) }

        levels[levels.count - 1] = ListLevel(
            indent: level.indent,
            content: level.content,
            number: opening.number.map { _ in (last.number ?? 0) + 1 }
        )
    }

    /// The mark an item is shown with, and its words without a task box.
    private static func marked(_ words: String, number: Int?) -> (mark: String, text: String) {
        if let number { return ("\(number). ", words) }

        guard let box = words.firstMatch(of: /^\[([ xX])\]\s+/) else { return ("• ", words) }

        return (box.1 == " " ? "☐ " : "☑ ", String(words[box.range.upperBound...]))
    }

    /// True where a line opens no block of its own, so it may run on from the one above.
    private func startsNothing(_ line: String) -> Bool {
        Self.fence(line) == nil && Self.heading(line) == nil && !Self.isRule(line) && Self.quoted(line) == nil
            && Self.item(line) == nil
    }
}
