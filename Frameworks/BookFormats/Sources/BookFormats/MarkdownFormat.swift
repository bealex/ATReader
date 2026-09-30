//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

/// Reading a book out of a Markdown file. Its headings are the book's chapters and their sections.
public struct MarkdownFormat: BookFormat {
    public init() {}

    /// What a picker offers when it is asking for a book of this format.
    public static var contentTypes: [UTType] {
        [
            UTType("net.daringfireball.markdown"),
            UTType(filenameExtension: "md", conformingTo: .plainText),
            UTType(filenameExtension: "markdown", conformingTo: .plainText),
        ].compactMap { $0 }
    }

    /// Text that is neither an archive nor markup. Markdown asks nothing more of a file.
    public func canRead(_ data: Data) -> Bool {
        guard !ZipArchive.isArchive(data), let text = Self.text(data), !text.contains("\u{0}") else { return false }

        return text.prefix(Self.sniffed).drop { $0.isWhitespace }.first != "<"
    }

    public func read(_ data: Data) async throws -> ReadBook {
        let book = try await Task.detached(priority: .userInitiated) {
            try Self.parse(data)
        }.value

        return ReadBook(book: book, source: data)
    }

    private static let sniffed = 512

    static func text(_ data: Data) -> String? {
        if data.starts(with: [ 0xFF, 0xFE ]) || data.starts(with: [ 0xFE, 0xFF ]) {
            return String(data: data, encoding: .utf16)
        }

        return String(data: data, encoding: .utf8)
    }

    static func parse(_ data: Data) throws -> ParsedBook {
        guard let text = text(data) else { throw BookFileError.unreadable }

        let document = MarkdownDocument(text)
        var writer = MarkdownSections(document)
        let sections = writer.sections()

        guard sections.contains(where: { $0.textLength > 0 }) else { throw BookFileError.notABook }

        let metadata = document.metadata
        let named = metadata["title"]?.nilWhenEmpty ?? writer.title
        let title = named ?? openingWords(of: sections)
        let authors = (metadata["author"] ?? metadata["authors"] ?? "")
            .split(separator: ",")
            .map(\.trimmed)
            .filter { !$0.isEmpty }

        return ParsedBook(
            title: title ?? String(localized: "Untitled"),
            authors: authors,
            annotation: metadata["description"]?.nilWhenEmpty,
            language: (metadata["lang"] ?? metadata["language"])?.nilWhenEmpty,
            series: nil,
            seriesOrder: nil,
            cover: nil,
            images: writer.pictures,
            sections: sections,
            // A document named by nothing is filed by its bytes, or every untitled note would land on
            // the same book.
            identifier: metadata["id"]?.nilWhenEmpty ?? (named == nil ? hash(data) : nil),
            format: "md"
        )
    }

    /// A title for a document with none: its first few words, marked as cut short where they are.
    private static func openingWords(of sections: [ParsedBook.Section]) -> String? {
        let text = sections.lazy
            .map { $0.html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression) }
            .first { !$0.trimmed.isEmpty }
        let words = (text ?? "").split(whereSeparator: \.isWhitespace).map(String.init)

        guard !words.isEmpty else { return nil }

        let kept = words.prefix(titleWords).joined(separator: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")

        guard words.count > titleWords else { return kept }

        return kept.trimmingCharacters(in: .punctuationCharacters) + "…"
    }

    private static let titleWords = 6

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// A document's blocks cut into chapters at its headings, each written as a chapter body.
struct MarkdownSections {
    /// What the document calls itself: a lone heading opening it, or failing that its first heading.
    private(set) var title: String?

    var pictures: [String: Data] { inline.pictures }

    private let blocks: [MarkdownBlock]
    private let footnotes: [String: String]
    /// Every heading's anchor, by where it stands among the blocks.
    private let anchors: [Int: String]
    /// Where the lone heading naming the document stands, if one does.
    private let titleHeading: Int?
    /// The heading levels the book is cut at: its chapters, then the sections inside them.
    private let divisions: [Int]
    /// What the front matter calls the document, which names whatever stands before its first chapter.
    private let named: String?
    private var inline: MarkdownInline

    private struct Heading {
        var index: Int
        var level: Int
        var text: String
    }

    /// A stretch of the blocks that becomes one section.
    private struct Piece {
        var title: String?
        var level: Int
        var blocks: Range<Int>
    }

    init(_ document: MarkdownDocument) {
        let blocks = document.blocks

        self.blocks = blocks
        footnotes = document.footnotes
        named = document.metadata["title"]?.nilWhenEmpty

        let headings = blocks.enumerated().compactMap { index, block -> Heading? in
            guard case let .heading(level, text) = block else { return nil }

            return Heading(index: index, level: level, text: text)
        }

        var anchors: [Int: String] = [:]
        var taken: [String: Int] = [:]

        for heading in headings {
            let slug = Self.slug(Self.plain(heading.text))
            let count = taken[slug, default: 0]

            taken[slug] = count + 1
            anchors[heading.index] = count == 0 ? slug : "\(slug)-\(count)"
        }

        self.anchors = anchors
        inline = MarkdownInline(footnotes: Set(footnotes.keys), anchors: Set(anchors.values))

        // A lone heading at the top level, with no text before it, names the document rather than
        // dividing it.
        let top = headings.map(\.level).min()
        let opening = headings.first.flatMap { first in
            first.level == top && headings.count { $0.level == top } == 1 && headings.count > 1
                && !blocks[..<first.index].contains(where: Self.carriesText) ? first : nil
        }

        titleHeading = opening?.index
        title = (opening ?? headings.first).map { Self.plain($0.text) }
        divisions = Array(Set(headings.filter { $0.index != opening?.index }.map(\.level)).sorted().prefix(2))
    }

    mutating func sections() -> [ParsedBook.Section] {
        var pieces: [Piece] = []
        var current = Piece(title: titleHeading.flatMap(heading(at:)) ?? named, level: 1, blocks: 0 ..< 0)

        for (index, block) in blocks.enumerated() {
            guard
                case let .heading(level, text) = block,
                index != titleHeading,
                let division = divisions.firstIndex(of: level)
            else { continue }

            current.blocks = current.blocks.lowerBound ..< index
            pieces.append(current)
            current = Piece(title: Self.plain(text), level: division + 1, blocks: index ..< index)
        }

        current.blocks = current.blocks.lowerBound ..< blocks.count
        pieces.append(current)

        return pieces.compactMap { piece in
            let html = html(blocks: piece.blocks, level: piece.level)
            let length = Self.stripped(html).count

            // What stands before the first chapter is kept only where it carries words of its own.
            let ownWords = length - (titleHeading == nil ? 0 : title?.count ?? 0)

            guard piece.blocks.lowerBound > 0 || ownWords > 0 else { return nil }

            return ParsedBook.Section(title: piece.title, html: html, textLength: length, level: piece.level)
        }
    }

    private func heading(at index: Int) -> String? {
        guard case let .heading(_, text) = blocks[index] else { return nil }

        return Self.plain(text)
    }

    // MARK: - Writing a chapter body

    private mutating func html(blocks range: Range<Int>, level: Int) -> String {
        var html = ""

        for index in range {
            if case let .heading(heading, text) = blocks[index] {
                let written =
                    index == titleHeading || index == range.lowerBound
                    ? level
                    : min(6, heading - (divisions.first ?? heading) + 1)
                let anchor = anchors[index].map { " data-anchor=\"\(MarkdownInline.escaped($0))\"" } ?? ""

                html += "<h\(written)\(anchor)>\(inline.html(text))</h\(written)>"
            } else {
                html += self.html(blocks[index], inset: false)
            }
        }

        return html + notes(pointedAtIn: html)
    }

    private mutating func html(_ block: MarkdownBlock, inset: Bool) -> String {
        let held = inset ? " data-inset=\"1\"" : ""

        switch block {
            case let .heading(_, text):
                return "<p\(held)><strong>\(inline.html(text))</strong></p>"
            case let .paragraph(text):
                return "<p\(held)>\(inline.html(text))</p>"
            case let .item(level, mark, text):
                return
                    "<p data-list=\"\(min(9, level))\"\(held)>\(MarkdownInline.escaped(mark))\(inline.html(text))</p>"
            case let .quote(inner):
                return inner.map { html($0, inset: true) }.joined()
            case let .code(lines):
                guard !lines.isEmpty else { return "" }

                return "<p data-verse=\"1\" data-inset=\"1\">\(lines.map(Self.codeLine).joined(separator: "<br>"))</p>"
            case .rule:
                return "<p style=\"text-align:center\">* * *</p>"
            case let .table(header, alignments, rows):
                return table(header: header, alignments: alignments, rows: rows)
            case let .html(markup):
                return markup
        }
    }

    private mutating func table(header: [String], alignments: [BookTable.Alignment], rows: [[String]]) -> String {
        func cells(_ row: [String], tag: String) -> String {
            row.enumerated().map { column, text in
                let alignment = column < alignments.count ? alignments[column] : .leading
                let style =
                    switch alignment {
                        case .leading: ""
                        case .center: " style=\"text-align:center\""
                        case .trailing: " style=\"text-align:right\""
                    }

                return "<\(tag)\(style)>\(inline.html(text))</\(tag)>"
            }.joined()
        }

        let body = rows.map { "<tr>\(cells($0, tag: "td"))</tr>" }.joined()

        return "<table><thead><tr>\(cells(header, tag: "th"))</tr></thead><tbody>\(body)</tbody></table>"
    }

    /// A line of code keeps its indent: leading spaces become figure spaces, which nothing collapses.
    private static func codeLine(_ line: String) -> String {
        let indent = line.prefix { $0 == " " }.count

        return String(repeating: "\u{2007}", count: indent) + MarkdownInline.escaped(String(line.dropFirst(indent)))
    }

    /// The footnotes a chapter's markers point at, written out under it the way a chapter carries them.
    private mutating func notes(pointedAtIn html: String) -> String {
        var written = ""
        var seen: Set<String> = []

        for match in html.matches(of: /href="#fn-([^"]+)"/) {
            let label = String(match.1)

            guard let text = footnotes[label], seen.insert(label).inserted else { continue }

            written += "<p id=\"\(MarkdownInline.escaped(MarkdownInline.noteId(label)))\">\(inline.html(text))</p>"
        }

        return written
    }

    // MARK: - Text

    private static func carriesText(_ block: MarkdownBlock) -> Bool {
        if case .heading = block { return false }

        return true
    }

    /// A heading's words without its markup, for the contents and for its anchor.
    private static func plain(_ text: String) -> String {
        var inline = MarkdownInline(footnotes: [], anchors: [])

        return stripped(inline.html(text))
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func stripped(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).trimmed
    }

    /// A heading's anchor as the places that write Markdown make one: lowercased, its punctuation
    /// dropped, its spaces turned into hyphens.
    static func slug(_ text: String) -> String {
        String(
            text.lowercased()
                .filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" || $0 == "_" }
                .map { $0 == " " ? "-" : $0 }
        )
    }
}
