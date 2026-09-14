//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Foundation

/// Reads a FictionBook 2 file into an ``ParsedBook``.
///
/// `XMLParser` rather than a document tree: these files run to megabytes, and everything wanted from
/// one is decided on the way past. Namespace processing is off so element names arrive as written,
/// which is what the `l:href` on an image is.
public enum FB2Parser {
    /// A book's chapters are the sections that hold its text.
    ///
    /// Sections nest, and a book with parts puts its chapters one level further in than a book without.
    /// So a section carrying sections of its own is a part rather than a chapter: what it holds directly
    /// (its title, an epigraph) becomes a short page of its own, and the sections inside it become the
    /// chapters. Splitting at the top level instead gave one 100,000-character chapter per part.
    /// Whether these bytes open like an FB2 file, without parsing the whole of one.
    ///
    /// The root element is what says so. Only the head is looked at: a book runs to megabytes, and
    /// deciding whether a picker should offer it is not worth reading them.
    public static func looksLikeFB2(_ data: Data) -> Bool {
        let head = data.prefix(4096)

        guard
            let text = String(data: head, encoding: .utf8) ?? String(data: head, encoding: .isoLatin1)
        else {
            return false
        }

        return text.contains("FictionBook")
    }

    public static func parse(_ data: Data) throws -> ParsedBook {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        parser.shouldProcessNamespaces = false

        guard parser.parse() else { throw BookFileError.malformed(parser.parserError?.localizedDescription) }

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
            /// A body after the first, which is where a file keeps its notes.
            case notes
            case binary
        }

        private var region: Region = .none
        /// Element names from the document root down, which is how a rule asks where it is.
        private var path: [String] = []
        /// The element the one being closed sits inside. Several elements share a name at different
        /// depths, and taking the wrong one silently files two books as one.
        private var parent: String? { path.count >= 2 ? path[path.count - 2] : nil }
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
        /// The pictures the body points at, by the name its `<image>` gives them.
        private var images: [String: Data] = [:]
        /// Every name an `<image>` in the text has asked for, so the binaries that answer to none of
        /// them are never decoded. FB2 puts its binaries after the text, so by then every name is known.
        private var wanted: Set<String> = []

        private var sections: [ParsedBook.Section] = []

        /// A section the parser is inside, filling.
        private struct Open {
            var title: String?
            var lines: [String] = []
            var length = 0
        }

        /// The sections the parser is inside, outermost first. Text lands in the innermost.
        private var open: [Open] = []
        /// The markup one blank line in the file is drawn as: a centred row of stars between the
        /// paragraphs it parts, the way the service's own chapters set one.
        private static let breakLine = "\(Setting.centred.tag)* * *</p>"

        /// Only the first `<body>` is the book. A body after it holds the notes the text points at,
        /// which are read into ``notes`` and handed to the chapters that refer to them.
        private var hasReadBody = false

        /// A stretch of the paragraph being read that the file marked: words it set apart, or a marker
        /// pointing at one of its notes.
        private struct Mark {
            let open: String
            let close: String
            let start: Int
            var stop: Int
        }

        /// The marks still open in the paragraph being read, innermost last, and the ones closed in it.
        private var openMarks: [Mark] = []
        private var marks: [Mark] = []

        /// The notes the file keeps in a body of their own, by the id its anchors point at.
        private var notes: [String: String] = [:]
        private var noteId: String?
        private var noteLines: [String] = []

        func book() throws -> ParsedBook {
            closeChapter()

            guard !sections.isEmpty else { throw BookFileError.notABook }

            return ParsedBook(
                title: bookTitle?.trimmed ?? String(localized: "Untitled"),
                authors: authors,
                annotation: annotation.isEmpty ? nil : annotation.joined(separator: "\n\n"),
                language: language?.trimmed,
                series: series?.trimmed.nilWhenEmpty,
                seriesOrder: seriesOrder,
                cover: cover,
                images: images,
                sections: Self.cutAtHeadings(sections).map(carryingNotes),
                identifier: documentId
            )
        }

        /// A book cut into the pieces its own headings mark, the finest divisions it gives.
        ///
        /// Some files mark their chapters with sections, some with headings inside one section, and
        /// some mark nothing at all. Where a section carries headings, those are divisions the book
        /// itself made, and they are what the reader is given: a chapter holding a whole book is
        /// composed from scratch every time it is opened, and a contents list of one line says nothing.
        ///
        /// A heading of nothing but marks names nothing, so the piece it opens carries no title. It is
        /// still a piece, and the contents calls it what it is rather than giving it a name it never
        /// had. Every piece cut out of a section stands one level below it.
        private static func cutAtHeadings(_ sections: [ParsedBook.Section]) -> [ParsedBook.Section] {
            sections.flatMap(cut(_:))
        }

        private static func cut(_ whole: ParsedBook.Section) -> [ParsedBook.Section] {
            let pieces = whole.html.components(separatedBy: "<h2>")

            guard pieces.count > 1 else { return [ whole ] }

            var cut: [ParsedBook.Section] = []

            for (index, piece) in pieces.enumerated() {
                // The first piece is whatever stood before any heading, and keeps the section's title.
                guard
                    index > 0
                else {
                    if !stripped(piece).isEmpty {
                        cut.append(made(title: whole.title, html: piece, level: whole.level))
                    }

                    continue
                }

                let parts = piece.components(separatedBy: "</h2>")
                let heading = parts.first.map(stripped) ?? ""
                let body = parts.dropFirst().joined(separator: "</h2>")
                let named = heading.contains(where: { $0.isLetter || $0.isNumber }) ? heading : nil

                cut.append(made(title: named, html: body, level: whole.level + 1))
            }

            return cut.count > 1 ? cut : [ whole ]
        }

        private static func made(title: String?, html: String, level: Int = 1) -> ParsedBook.Section {
            ParsedBook.Section(title: title, html: html, textLength: stripped(html).count, level: level)
        }

        /// The words of a fragment, with its markup off, for weighing how long a piece runs.
        private static func stripped(_ html: some StringProtocol) -> String {
            String(html)
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// A chapter with the notes its own text points at written under it.
        ///
        /// A file keeps its notes in a body of their own, at the end, where the chapter referring to
        /// them is long past. Carrying each note down to the chapter that uses it is what lets a
        /// chapter from a file be read exactly the way one from the service is.
        private func carryingNotes(_ section: ParsedBook.Section) -> ParsedBook.Section {
            guard !notes.isEmpty else { return section }

            let used = notes.keys.filter { section.html.contains("href=\"#\($0)\"") }.sorted()

            guard !used.isEmpty else { return section }

            let carried = used.map { "<div id=\"\(Self.escaped($0))\">\(Self.escaped(notes[$0] ?? ""))</div>" }

            return ParsedBook.Section(
                title: section.title,
                html: section.html + carried.joined(),
                textLength: section.textLength
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

            if !startedDescription(element, attributes: attributes) {
                startedBody(element, attributes: attributes)
            }

            // Every block of text starts empty, so the characters of the one before it never leak in.
            if Self.blocks.contains(element) {
                text = ""
                marks = []
                openMarks = []
            }
        }

        /// Handles what the file says about itself. Reports whether the element was one of those.
        private func startedDescription(_ element: String, attributes: [String: String]) -> Bool {
            switch element {
                case "title-info": region = .titleInfo
                case "document-info": region = .documentInfo
                case "binary": startBinary(attributes)
                case "author" where region == .titleInfo: authorParts = [:]
                case "sequence": readSequence(attributes)
                case "image" where path.contains("coverpage"): coverId = Self.reference(in: attributes)
                default: return false
            }

            return true
        }

        private func startedBody(_ element: String, attributes: [String: String]) {
            switch element {
                case "body": startBody()
                case "section" where region == .body: startSection()
                case "empty-line" where region == .body: markBreak()
                case "image" where region == .body: startImage(attributes)
                case "a" where region == .body: startMark(Self.note(in: attributes))
                case "emphasis" where region == .body: startMark(Self.emphasis)
                case "strong" where region == .body: startMark(Self.strength)
                case "section" where region == .notes: startNote(attributes)
                default: break
            }
        }

        /// A body is opened the way a part is, so that what it holds before its first section has
        /// somewhere to land: a picture, the book's epigraphs, a dedication. The first section closes
        /// that into a page of its own, ahead of the first chapter.
        private func startBody() {
            region = hasReadBody ? .notes : .body

            guard region == .body else { return }

            open.append(Open())
        }

        /// True where text is landing inside a section rather than in the body's own front matter.
        private var inSection: Bool { open.count > 1 }

        /// Opens a mark over whatever the paragraph reads from here. An element that marks nothing
        /// opens a blank one all the same, so the tag closing it has its own to close.
        private func startMark(_ tags: (open: String, close: String)?) {
            openMarks.append(Mark(
                open: tags?.open ?? "",
                close: tags?.close ?? "",
                start: text.count,
                stop: text.count
            ))
        }

        private static let emphasis = (open: "<em>", close: "</em>")
        private static let strength = (open: "<strong>", close: "</strong>")

        /// Elements that mark a stretch of a paragraph rather than holding one of their own.
        private static let marking: Set<String> = [ "a", "emphasis", "strong" ]

        /// The tags that wrap a marker pointing into the book's own notes. Anything else an `<a>` may
        /// point at is not one.
        private static func note(in attributes: [String: String]) -> (open: String, close: String)? {
            guard let target = noteTarget(in: attributes) else { return nil }

            return (open: "<a href=\"#\(escaped(target))\">", close: "</a>")
        }

        private func startNote(_ attributes: [String: String]) {
            noteId = attributes["id"]?.trimmed.nilWhenEmpty
            noteLines = []
        }

        private func endMark() {
            guard var mark = openMarks.popLast() else { return }

            mark.stop = text.count

            guard !mark.open.isEmpty, mark.stop > mark.start else { return }

            marks.append(mark)
        }

        private func endNote() {
            defer {
                noteId = nil
                noteLines = []
            }

            guard let noteId, !noteLines.isEmpty else { return }

            notes[noteId] = noteLines.joined(separator: " ")
        }

        /// The note an anchor points at: a reference into the file, rather than a link out of it.
        private static func noteTarget(in attributes: [String: String]) -> String? {
            let href = attributes["l:href"] ?? attributes["xlink:href"] ?? attributes["href"]

            guard let href, href.hasPrefix("#") else { return nil }

            return String(href.dropFirst()).trimmed.nilWhenEmpty
        }

        /// A blank line in the file is a break in the scene, written where the book put it.
        ///
        /// Held over until the next paragraph, as it once was, a picture or the end of a section
        /// swallowed it and the reader met the break further down the chapter than the book wrote it,
        /// or never met it at all. Nothing may move what a book set in order.
        ///
        /// A break opening a block divides nothing, having nothing above it, and a run of blank lines
        /// is one break rather than several.
        private func markBreak() {
            guard !open.isEmpty, let last = open[open.count - 1].lines.last else { return }
            guard last != Self.breakLine else { return }

            open[open.count - 1].lines.append(Self.breakLine)
        }

        /// A picture in the text becomes a block of its own, named after the binary that holds it.
        private func startImage(_ attributes: [String: String]) {
            guard !open.isEmpty, let name = Self.reference(in: attributes) else { return }
            // A body opening with the plate the description already named as the cover is repeating
            // the one the reader shows before the first page.
            guard inSection || name != coverId else { return }

            wanted.insert(name)
            open[open.count - 1].lines.append("<img src=\"\(Self.escaped(name))\">")
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
                // The document's own id, not the one inside `<publisher>`. Those files carry both, and
                // the publisher's is the same in every book it ever published.
                case .documentInfo where element == "id" && parent == "document-info":
                    documentId = text.trimmed.nilWhenEmpty
                case .body: endBodyElement(element)
                case .notes where Self.blocks.contains(element):
                    if let line = text.trimmed.nilWhenEmpty { noteLines.append(line) }
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
                case "body" where region == .notes: region = .none
                case "section" where region == .notes: endNote()
                case let name where Self.marking.contains(name) && region == .body: endMark()
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
                    // A translator carries the same name elements as an author, one level along.
                    if parent == "author" { authorParts[element] = text.trimmed }
                default: break
            }
        }

        private func readSequence(_ attributes: [String: String]) {
            guard let name = attributes["name"]?.trimmed.nilWhenEmpty else { return }
            // The first sequence named wins the series, since a book belongs to one. The number is
            // taken from whichever copy of that sequence carries one: a file often repeats it under
            // `publish-info`, and sometimes only the repeat states the volume.
            guard
                series == nil
            else {
                if seriesOrder == nil, name == series { seriesOrder = Self.volume(in: attributes) }

                return
            }

            series = name
            seriesOrder = Self.volume(in: attributes)
        }

        /// The volume a sequence states, where it states one.
        private static func volume(in attributes: [String: String]) -> Int? {
            attributes["number"].flatMap { Int($0.trimmed) }
        }

        private func endAuthor() {
            let name =
                [ "first-name", "middle-name", "last-name" ]
                .compactMap { authorParts[$0]?.nilWhenEmpty }
                .joined(separator: " ")
                .nilWhenEmpty ?? authorParts["nickname"]?.nilWhenEmpty

            guard let name else { return }

            authors.append(name)
            authorParts = [:]
        }

        // MARK: - The text itself

        private func startSection() {
            // A section that turns out to hold sections is a part, and what it holds directly is
            // either a page of its own or the head of the section opening under it. Settling that here
            // rather than when the part closes keeps the book in order: its children close first.
            let opening = open.isEmpty ? Open() : leading(from: &open[open.count - 1])

            open.append(opening)
        }

        /// What a part holds directly, where it stands over the section opening under it rather than
        /// on a page of its own: the epigraphs a book carries above chapter one. Anything named is a
        /// page, and so is a plate, which is something to look at rather than something to read.
        private func leading(from part: inout Open) -> Open {
            guard
                part.title == nil,
                !part.lines.contains(where: { $0.hasPrefix("<img") })
            else {
                emit(&part, keepingTitle: false)

                return Open()
            }

            defer {
                part.lines = []
                part.length = 0
            }

            return Open(lines: part.lines, length: part.length)
        }

        private func endSection() {
            guard var section = open.popLast() else { return }

            emit(&section, keepingTitle: true)
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

            sections.append(ParsedBook.Section(
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
                        append(text, setting: setting)
                    }
                // A subtitle carrying nothing but the marks of a scene break is a break, whatever the
                // file calls it. Read as a title it becomes a heading, which cuts the chapter in two
                // wherever the book merely parted two scenes.
                case "subtitle" where BookHTML.isSceneBreak(text):
                    markBreak()
                case "subtitle":
                    append(text, setting: .centred, titleLevel: 2)
                // Whose words they were, set apart from them the way a quotation names its source.
                case "text-author":
                    append(text, setting: setting, emphasised: true, sourcing: true)
                default: break
            }
        }

        /// The first line of a section's title names it. Any line after that stays in the text, so a
        /// title set as several paragraphs keeps the rest of itself.
        private func addTitleLine() {
            // A body's own title names the book rather than a chapter, and the reader shows that
            // before the first page whatever the file says.
            guard inSection, let line = text.trimmed.nilWhenEmpty else { return }
            guard
                open[open.count - 1].title == nil
            else {
                return append(line, setting: .centred)
            }

            open[open.count - 1].title = line
        }

        /// How a block is set, which comes from where the file put it rather than from any styling.
        private enum Setting {
            case plain
            case centred
            /// Held off the edge the way a passage quoted at length is, which is what an epigraph is.
            case inset

            var tag: String {
                switch self {
                    case .plain: "<p>"
                    case .centred: "<p style=\"text-align:center\">"
                    case .inset: "<p data-inset=\"1\">"
                }
            }

            /// The same block, naming whose words stood above it rather than adding to them.
            var sourcing: String { tag.replacingOccurrences(of: "<p", with: "<p data-source=\"1\"") }
        }

        /// True where the block being read is a line of verse, which the file says outright: a `<v>`
        /// inside a `<poem>`. Nothing is guessed at from how short a line is.
        private var isVerse: Bool { path.contains("poem") }

        /// How whatever is being read now is set, decided by what it stands inside.
        private var setting: Setting {
            if Self.quotedParents.contains(where: path.contains) { return .inset }

            return Self.centredParents.contains(where: path.contains) ? .centred : .plain
        }

        private func append(
            _ raw: String,
            setting: Setting,
            titleLevel: Int? = nil,
            emphasised: Bool = false,
            sourcing: Bool = false
        ) {
            guard !open.isEmpty, let line = raw.trimmed.nilWhenEmpty else { return }

            let marked = marks.isEmpty ? Self.escaped(line) : Self.escaped(raw, marking: marks).trimmed
            let body = emphasised ? "<em>\(marked)</em>" : marked

            // A title is written as a heading, which is what carries its level across to the reader.
            // Everything else is a paragraph, set the way the file put it.
            if let titleLevel {
                open[open.count - 1].lines.append("<h\(titleLevel)>\(body)</h\(titleLevel)>")
            } else {
                let tag = sourcing ? setting.sourcing : setting.tag

                open[open.count - 1].lines.append("\(Self.versed(tag, isVerse))\(body)</p>")
            }
            open[open.count - 1].length += line.count
        }

        /// The same block, marked as a line the book set as verse. Verse keeps whatever else it is,
        /// since a poem quoted as an epigraph is both held off the edge and broken into lines.
        private static func versed(_ tag: String, _ isVerse: Bool) -> String {
            guard isVerse else { return tag }

            return tag.replacingOccurrences(of: "<p", with: "<p data-verse=\"1\"")
        }

        /// The paragraph escaped, with every mark the file made wrapped round the words it covered.
        ///
        /// The words keep the characters the file gave them: a reading position counts them, so nothing
        /// is added to the text or taken out of it, and a note's marker is set as the file wrote it
        /// rather than renumbered.
        private static func escaped(_ text: String, marking marks: [Mark]) -> String {
            let characters = Array(text)
            var opening: [Int: [Mark]] = [:]
            var closing: [Int: [Mark]] = [:]

            for mark in marks where mark.start >= 0 && mark.stop <= characters.count {
                opening[mark.start, default: []].append(mark)
                closing[mark.stop, default: []].append(mark)
            }

            var result = ""
            var cursor = 0

            for point in Set(opening.keys).union(closing.keys).sorted() {
                result += escaped(String(characters[cursor ..< point]))
                // Closes before opens, and the innermost of each first, so marks meeting at one point
                // nest rather than cross.
                for mark in (closing[point] ?? []).sorted(by: { $0.start > $1.start }) { result += mark.close }

                for mark in (opening[point] ?? []).sorted(by: { $0.stop > $1.stop }) { result += mark.open }

                cursor = point
            }

            return result + escaped(String(characters[cursor...]))
        }

        // MARK: - The cover

        private func startBinary(_ attributes: [String: String]) {
            binaryId = attributes["id"]
            binary = ""

            guard let binaryId, attributes["content-type"]?.hasPrefix("image/") ?? true else { return }
            // Only the cover and the pictures the text actually points at. Anything else would be
            // decoded and then thrown away.
            guard (cover == nil && binaryId == coverId) || wanted.contains(binaryId) else { return }

            region = .binary
        }

        private func endBinary() {
            defer {
                binary = ""
                binaryId = nil
            }

            guard region == .binary, let binaryId else { return }

            region = .none

            guard let data = Data(base64Encoded: binary, options: .ignoreUnknownCharacters) else { return }

            if binaryId == coverId, cover == nil { cover = data }

            if wanted.contains(binaryId) { images[binaryId] = data }
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

        /// Anything inside one of these is a passage quoted rather than told, and is held off the edge
        /// the way the reader already holds one: an epigraph over a chapter, a citation inside it.
        private static let quotedParents: Set<String> = [ "epigraph", "cite" ]

        /// Anything inside one of these is set centred.
        private static let centredParents: Set<String> = [ "poem" ]

        private static func escaped(_ text: String) -> String {
            text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
    }
}
