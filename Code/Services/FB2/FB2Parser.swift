//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// Reads a FictionBook 2 file into an ``FB2Book``.
///
/// `XMLParser` rather than a document tree: these files run to megabytes, and everything wanted from
/// one is decided on the way past. Namespace processing is off so element names arrive as written,
/// which is what the `l:href` on an image is.
enum FB2Parser {
    /// A book's chapters are the sections that hold its text.
    ///
    /// Sections nest, and a book with parts puts its chapters one level further in than a book without.
    /// So a section carrying sections of its own is a part rather than a chapter: what it holds directly
    /// (its title, an epigraph) becomes a short page of its own, and the sections inside it become the
    /// chapters. Splitting at the top level instead gave one 100,000-character chapter per part.
    static func parse(_ data: Data) throws -> FB2Book {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        parser.shouldProcessNamespaces = false

        guard parser.parse() else { throw FB2Error.malformed(parser.parserError?.localizedDescription) }

        return try builder.book()
    }

    /// Collects the file into a book as the parser walks it.
    ///
    /// Never crosses an isolation boundary: it is made, driven and read inside ``parse(_:)``, which is
    /// synchronous, so it needs no `Sendable` of its own.
    private final class Builder: NSObject, XMLParserDelegate {
        private enum Region {
            case none
            case titleInfo
            case documentInfo
            case body
            case binary
        }

        private var region: Region = .none
        /// Element names from the document root down, which is how a rule asks where it is.
        private var path: [String] = []
        private var text = ""

        private var bookTitle: String?
        private var language: String?
        private var series: String?
        private var seriesOrder: Int?
        private var annotation: [String] = []
        private var coverId: String?

        private var authorParts: [String: String] = [:]
        private var authors: [String] = []
        /// The file's own identifier, which stays the same across the editions of one book. It is what
        /// lets a corrected file land on the book it corrects rather than beside it.
        private var documentId: String?

        private var cover: Data?
        private var binaryId: String?
        private var binary = ""

        private var sections: [FB2Book.Section] = []

        /// A section the parser is inside, filling.
        private struct Open {
            var title: String?
            var lines: [String] = []
            var length = 0
        }

        /// The sections the parser is inside, outermost first. Text lands in the innermost.
        private var open: [Open] = []
        /// Runs of `<empty-line/>` collapse into a single scene break.
        private var pendingBreak = false

        /// Only the first `<body>` is the book. A second one holds the footnotes, which the reader has
        /// nowhere to show.
        private var hasReadBody = false

        func book() throws -> FB2Book {
            closeChapter()

            guard !sections.isEmpty else { throw FB2Error.notABook }

            return FB2Book(
                title: bookTitle?.trimmed ?? String(localized: "Untitled"),
                authors: authors,
                annotation: annotation.isEmpty ? nil : annotation.joined(separator: "\n\n"),
                language: language?.trimmed,
                series: series?.trimmed.nilWhenEmpty,
                seriesOrder: seriesOrder,
                cover: cover,
                sections: sections,
                identifier: documentId
            )
        }

        // MARK: - Walking the file

        func parser(
            _ parser: XMLParser,
            didStartElement element: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String]
        ) {
            path.append(element)

            if !startedDescription(element, attributes: attributes) { startedBody(element) }

            // Every block of text starts empty, so the characters of the one before it never leak in.
            if Self.blocks.contains(element) { text = "" }
        }

        /// Handles what the file says about itself. Reports whether the element was one of those.
        private func startedDescription(_ element: String, attributes: [String: String]) -> Bool {
            switch element {
                case "title-info": region = .titleInfo
                case "document-info": region = .documentInfo
                case "binary": startBinary(attributes)
                case "author" where region == .titleInfo: authorParts = [:]
                case "sequence" where region == .titleInfo: readSequence(attributes)
                case "image" where path.contains("coverpage"): coverId = Self.reference(in: attributes)
                default: return false
            }

            return true
        }

        private func startedBody(_ element: String) {
            switch element {
                case "body" where !hasReadBody: region = .body
                case "section" where region == .body: startSection()
                case "empty-line" where region == .body: pendingBreak = true
                default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if region == .binary {
                binary += string
            } else {
                text += string
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement element: String,
            namespaceURI: String?,
            qualifiedName: String?
        ) {
            defer {
                if !path.isEmpty { path.removeLast() }
            }

            closed(element)

            switch region {
                case .titleInfo: endTitleInfoElement(element)
                case .documentInfo where element == "id": documentId = text.trimmed.nilWhenEmpty
                case .body: endBodyElement(element)
                default: break
            }
        }

        /// Closes whichever part of the file the element belongs to, before its own text is read off.
        private func closed(_ element: String) {
            switch element {
                case "title-info", "document-info": region = .none
                case "body" where region == .body:
                    closeChapter()
                    region = .none
                    hasReadBody = true
                case "binary": endBinary()
                case "author" where region == .titleInfo: endAuthor()
                case "section" where region == .body: endSection()
                default: break
            }
        }

        // MARK: - What the book is

        private func endTitleInfoElement(_ element: String) {
            switch element {
                case "book-title": bookTitle = text.trimmed
                case "lang": language = text.trimmed
                case "p" where path.contains("annotation"):
                    if let line = text.trimmed.nilWhenEmpty { annotation.append(line) }
                case "first-name", "middle-name", "last-name", "nickname":
                    authorParts[element] = text.trimmed
                default: break
            }
        }

        private func readSequence(_ attributes: [String: String]) {
            // The first sequence named wins. A file often repeats it under `publish-info`, and a book
            // belongs to one series here.
            guard series == nil, let name = attributes["name"]?.trimmed.nilWhenEmpty else { return }

            series = name
            seriesOrder = attributes["number"].flatMap { Int($0.trimmed) }
        }

        private func endAuthor() {
            let name = [ "first-name", "middle-name", "last-name" ]
                .compactMap { authorParts[$0]?.nilWhenEmpty }
                .joined(separator: " ")
                .nilWhenEmpty ?? authorParts["nickname"]?.nilWhenEmpty

            guard let name else { return }

            authors.append(name)
            authorParts = [:]
        }

        // MARK: - The text itself

        private func startSection() {
            // A section that turns out to hold sections is a part, and what it holds directly is its
            // own page. Emitting that here rather than when it closes is what keeps the book in order:
            // its children close before it does.
            if !open.isEmpty { emit(&open[open.count - 1], keepingTitle: false) }

            open.append(Open())
            pendingBreak = false
        }

        private func endSection() {
            guard var section = open.popLast() else { return }

            emit(&section, keepingTitle: true)
            pendingBreak = false
        }

        /// Closes what a section holds into a chapter, unless it holds nothing worth a page.
        ///
        /// A part keeps its title for the page it opens and gives it up afterwards, so the chapters
        /// under it aren't each headed with the part's name.
        private func emit(_ section: inout Open, keepingTitle: Bool) {
            defer {
                section.lines = []
                section.length = 0

                if !keepingTitle { section.title = nil }
            }

            guard !section.lines.isEmpty || section.title != nil else { return }

            sections.append(FB2Book.Section(
                title: section.title,
                html: section.lines.joined(),
                textLength: section.length
            ))
        }

        private func closeChapter() {
            while !open.isEmpty { endSection() }
        }

        private func endBodyElement(_ element: String) {
            switch element {
                case "p", "v":
                    // A paragraph inside a title names the section rather than opening it.
                    if path.contains("title") {
                        addTitleLine()
                    } else {
                        append(text, centered: Self.centeredParents.contains(where: path.contains))
                    }
                case "subtitle", "text-author":
                    append(text, centered: true)
                default: break
            }
        }

        /// The first line of a section's title names it. Any line after that stays in the text, so a
        /// title set as several paragraphs keeps the rest of itself.
        private func addTitleLine() {
            guard !open.isEmpty, let line = text.trimmed.nilWhenEmpty else { return }

            guard
                open[open.count - 1].title == nil
            else {
                return append(line, centered: true)
            }

            open[open.count - 1].title = line
        }

        private func append(_ raw: String, centered: Bool) {
            guard !open.isEmpty, let line = raw.trimmed.nilWhenEmpty else { return }

            // A run of blank lines is a scene break, which this reader draws the way the service's own
            // chapters do: one centred row of stars between the paragraphs it parts.
            if pendingBreak, !open[open.count - 1].lines.isEmpty {
                open[open.count - 1].lines.append("<p style=\"text-align:center\">* * *</p>")
            }

            pendingBreak = false
            open[open.count - 1].lines.append(
                centered
                    ? "<p style=\"text-align:center\">\(Self.escaped(line))</p>"
                    : "<p>\(Self.escaped(line))</p>"
            )
            open[open.count - 1].length += line.count
        }

        // MARK: - The cover

        private func startBinary(_ attributes: [String: String]) {
            binaryId = attributes["id"]
            binary = ""

            // Only the cover is kept. Chapter illustrations have nowhere to go in a text reader, and a
            // book's worth of them would sit in the database for good.
            guard cover == nil, binaryId != nil, binaryId == coverId else { return }

            region = .binary
        }

        private func endBinary() {
            defer {
                binary = ""
                binaryId = nil
            }

            guard region == .binary else { return }

            region = .none
            cover = Data(base64Encoded: binary, options: .ignoreUnknownCharacters)
        }

        /// The id a `coverpage` image points at, less the `#` that makes it a reference.
        private static func reference(in attributes: [String: String]) -> String? {
            let href = attributes["l:href"] ?? attributes["xlink:href"] ?? attributes["href"]

            guard let href, href.hasPrefix("#") else { return href }

            return String(href.dropFirst())
        }

        /// Elements whose characters are one block of text rather than part of the one around them.
        private static let blocks: Set<String> = [
            "p", "v", "subtitle", "text-author", "book-title", "lang", "id",
            "first-name", "middle-name", "last-name", "nickname",
        ]

        /// Anything inside one of these is set centred, the way the reader already sets an epigraph.
        private static let centeredParents: Set<String> = [ "epigraph", "poem" ]

        private static func escaped(_ text: String) -> String {
            text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
    }
}

extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    fileprivate var nilWhenEmpty: String? { isEmpty ? nil : self }
}
