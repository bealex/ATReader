//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// A note the text points at: what it says, and the marker standing for it on the page.
public struct BookNote: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    /// The marker as the text itself writes it, `1` or `[1]`. Kept rather than renumbered, because a
    /// reading position counts these characters.
    public let marker: String
    public let text: String

    public init(id: String, marker: String, text: String) {
        self.id = id
        self.marker = marker
        self.text = text
    }
}

/// Where a note's marker stands in a paragraph's own text.
///
/// Counted in the text as it arrived, the way a reading position is, so the typesetter's own soft
/// hyphens and word joiners don't move it.
public struct NoteMark: Codable, Sendable, Hashable {
    public let location: Int
    public let length: Int
    public let noteId: String

    public init(location: Int, length: Int, noteId: String) {
        self.location = location
        self.length = length
        self.noteId = noteId
    }

    public var range: NSRange { NSRange(location: location, length: length) }
}

/// A stretch of a paragraph set off the line: a formula's lowered figure, or a lifted one.
///
/// Counted the way a note marker is, in the characters the text arrived with, so a reading position
/// means the same whether or not the typesetter has been through it.
public struct ScriptMark: Codable, Sendable, Hashable {
    public enum Place: String, Codable, Sendable {
        case below
        case above
    }

    public let location: Int
    public let length: Int
    public let place: Place

    public init(location: Int, length: Int, place: Place) {
        self.location = location
        self.length = length
        self.place = place
    }

    public var range: NSRange { NSRange(location: location, length: length) }
}

/// One laid-out block of a chapter: a paragraph of text, or a picture standing on its own.
public struct Paragraph: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let text: String
    /// Author-centred lines (scene breaks, epigraphs) carry a `text-align: center` style.
    public let isCentered: Bool
    /// What the block's `<img>` pointed at, on a block that is a picture rather than text. Whoever
    /// lays the chapter out decides what a source resolves to, and drops the block where nothing
    /// answers to it.
    public let imageSource: String?
    /// What level of title this block is, or nothing where it is ordinary text. One is the biggest.
    public let titleLevel: Int?
    /// The note markers standing in this paragraph, in the order they stand in it.
    public let notes: [NoteMark]
    /// The stretches of it set off the line, in the order they stand in it.
    public let scripts: [ScriptMark]

    public init(
        id: Int,
        text: String,
        isCentered: Bool,
        imageSource: String? = nil,
        titleLevel: Int? = nil,
        notes: [NoteMark] = [],
        scripts: [ScriptMark] = []
    ) {
        self.id = id
        self.text = text
        self.isCentered = isCentered
        self.imageSource = imageSource
        self.titleLevel = titleLevel
        self.notes = notes
        self.scripts = scripts
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        isCentered = try container.decode(Bool.self, forKey: .isCentered)
        imageSource = try container.decodeIfPresent(String.self, forKey: .imageSource)
        titleLevel = try container.decodeIfPresent(Int.self, forKey: .titleLevel)
        // A chapter prepared before notes were read carries none, and is still good text.
        notes = try container.decodeIfPresent([ NoteMark ].self, forKey: .notes) ?? []
        // As with the notes: a chapter prepared before these were read carries none.
        scripts = try container.decodeIfPresent([ ScriptMark ].self, forKey: .scripts) ?? []
    }

    public var isImage: Bool { imageSource != nil }
}

/// A chapter as its markup gives it: the blocks to set, and the notes their text points at.
public struct ChapterMarkup: Sendable {
    public let paragraphs: [Paragraph]
    public let notes: [String: BookNote]

    public init(paragraphs: [Paragraph], notes: [String: BookNote]) {
        self.paragraphs = paragraphs
        self.notes = notes
    }
}

/// A stretch of the markup being read.
private typealias HTMLRange = Range<String.Index>

/// Turns the HTML a chapter arrives in into flat paragraphs a reader view can lay out.
///
/// Chapter bodies use a small, predictable subset — `<p>`, `<br>`, `<span>`, emphasis and the odd `<img>` —
/// so a targeted pass beats pulling in a full HTML stack, and it keeps the work off the main actor.
public enum BookHTML {
    /// What level of title a block is, or nothing where it is ordinary text.
    ///
    /// The markup says, and only the markup. A paragraph is centred for all sorts of reasons, so what
    /// one holds is never asked: a row of stars is a title because the book wrote it as one, not
    /// because of the characters in it.
    private static func titleLevel(inside attributes: String) -> Int? {
        guard let found = attributes.range(of: "data-title=\"[1-6]\"", options: .regularExpression) else { return nil }

        return Int(attributes[found].suffix(2).prefix(1))
    }

    /// Rewrites `<h1>`…`<h6>` as paragraphs carrying their level, so one walk reads the whole body.
    private static func levelling(_ html: String) -> String {
        var result = html.replacingOccurrences(
            of: "<h([1-6])(\\s[^>]*)?>",
            with: "<p data-title=\"$1\" style=\"text-align:center\"$2>",
            options: [ .regularExpression, .caseInsensitive ]
        )

        result = result.replacingOccurrences(
            of: "</h[1-6]\\s*>",
            with: "</p>",
            options: [ .regularExpression, .caseInsensitive ]
        )
        return result
    }

    /// A chapter's blocks alone, for text that carries no notes worth showing: an annotation, a blurb.
    public static func paragraphs(from html: String) -> [Paragraph] { chapter(from: html).paragraphs }

    private enum Block {
        case text(attributes: String, inner: String)
        case picture(String)
    }

    /// Walks the body once, taking paragraphs and pictures in the order they stand in it.
    private static func blocks(in html: String) -> [Block] {
        var blocks: [Block] = []
        var cursor = html.startIndex
        // Each is kept until the cursor passes it. Looked for afresh from every paragraph, a tag the rest
        // of the chapter doesn't have costs a read of the whole rest of it, once per paragraph.
        var paragraph = html.range(of: "<p", options: .caseInsensitive)
        var picture = html.range(of: "<img", options: .caseInsensitive)

        while cursor < html.endIndex {
            if let passed = paragraph, passed.lowerBound < cursor {
                paragraph = html.range(of: "<p", options: .caseInsensitive, range: cursor ..< html.endIndex)
            }

            if let passed = picture, passed.lowerBound < cursor {
                picture = html.range(of: "<img", options: .caseInsensitive, range: cursor ..< html.endIndex)
            }

            // A picture standing on its own, where it comes before the next paragraph. One set inside a
            // paragraph is left to that paragraph.
            if let picture, paragraph.map({ picture.lowerBound < $0.lowerBound }) ?? true {
                guard let close = html.range(of: ">", range: picture.upperBound ..< html.endIndex) else { break }

                if let source = source(in: html[picture.upperBound ..< close.lowerBound]) {
                    blocks.append(.picture(source))
                }

                cursor = close.upperBound
                continue
            }

            guard
                let paragraph,
                let openEnd = html.range(of: ">", range: paragraph.upperBound ..< html.endIndex)
            else { break }

            let attributes = String(html[paragraph.upperBound ..< openEnd.lowerBound])
                .replacingOccurrences(of: " ", with: "")
                .lowercased()
            let closeRange = html.range(
                of: "</p>",
                options: .caseInsensitive,
                range: openEnd.upperBound ..< html.endIndex
            )
            let inner = String(html[openEnd.upperBound ..< (closeRange?.lowerBound ?? html.endIndex)])

            blocks.append(.text(attributes: attributes, inner: inner))
            // A picture set inside a paragraph stands under it rather than going the way of the rest
            // of the markup.
            blocks.append(contentsOf: pictures(in: inner))
            cursor = closeRange?.upperBound ?? html.endIndex
        }

        return blocks
    }

    private static func pictures(in fragment: String) -> [Block] {
        var blocks: [Block] = []
        var cursor = fragment.startIndex

        while let open = fragment.range(of: "<img", options: .caseInsensitive, range: cursor ..< fragment.endIndex) {
            guard let close = fragment.range(of: ">", range: open.upperBound ..< fragment.endIndex) else { break }

            if let source = source(in: fragment[open.upperBound ..< close.lowerBound]) {
                blocks.append(.picture(source))
            }

            cursor = close.upperBound
        }

        return blocks
    }

    /// The `src` of an `<img>`, taken from the tag's attributes.
    private static func source(in attributes: some StringProtocol) -> String? {
        guard let key = attributes.range(of: "src", options: .caseInsensitive) else { return nil }

        let rest = attributes[key.upperBound...].drop { $0 == " " || $0 == "=" }

        guard let quote = rest.first, quote == "\"" || quote == "'" else { return nil }

        let value = rest.dropFirst().prefix { $0 != quote }
        return value.isEmpty ? nil : decodeEntities(in: String(value))
    }

    private static func plainText(from fragment: String) -> String {
        var text = fragment

        // A space, not a newline: a newline ends the paragraph as far as the typesetter is concerned.
        for lineBreak in [ "<br>", "<br/>", "<br />" ] {
            text = text.replacingOccurrences(of: lineBreak, with: " ", options: .caseInsensitive)
        }

        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = decodeEntities(in: text)
        // HTML reads any run of these as one space. The non-breaking space is left alone, being the one
        // piece of white space the text means.
        text = text.replacingOccurrences(of: "[ \t\n\r\u{000B}\u{000C}]+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let entities = [
        "&nbsp;": "\u{00A0}",
        "&amp;": "&",
        "&lt;": "<",
        "&gt;": ">",
        "&quot;": "\"",
        "&apos;": "'",
        "&laquo;": "«",
        "&raquo;": "»",
        "&mdash;": "—",
        "&ndash;": "–",
        "&hellip;": "…",
        "&#39;": "'",
    ]

    private static func decodeEntities(in text: String) -> String {
        guard text.contains("&") else { return text }

        var result = text

        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }

        return result
    }

    /// A row of asterisks and nothing else, which stands for a break in the scene.
    ///
    /// Centred wherever it is found: most of the service's books align it themselves, and the rest
    /// leave it in an ordinary justified paragraph, where it would otherwise sit at the margin.
    private static func isSceneBreak(_ text: String) -> Bool {
        let marks = text.filter { !$0.isWhitespace }

        return !marks.isEmpty && marks.count <= separatorMarks && marks.allSatisfy { $0 == "*" }
    }

    /// The longest row of marks read as a scene break rather than as text.
    private static let separatorMarks = 7

    // MARK: - The notes the text points at

    /// A chapter's blocks and the notes standing behind them.
    ///
    /// A note is an anchor into the chapter itself, `<a href="#n1">1</a>`, with the note's own words
    /// further down under `id="n1"`. Those words are lifted out and the block holding them dropped, so
    /// a note reads where it is referred to rather than as a stray paragraph at the foot of the
    /// chapter. An anchor carrying its note on a `title` attribute instead is read the same way.
    ///
    /// The marker keeps exactly the characters the text gave it. A reading position is an offset into
    /// this text, so a renumbered marker would move the reader's place in every book on the device.
    public static func chapter(from html: String) -> ChapterMarkup {
        let html = levelling(html)
        let bodies = noteBodies(among: referencedIds(in: html), in: html)
        let body = removing(bodies.values.map(\.range), from: html)
        let blocks = blocks(in: body)
        var notes = bodies.compactMapValues { $0.text.isEmpty ? nil : BookNote(id: $0.id, marker: "", text: $0.text) }
        var result: [Paragraph] = []
        var index = 0

        for block in blocks {
            switch block {
                case let .picture(source):
                    result.append(Paragraph(id: index, text: "", isCentered: true, imageSource: source))
                    index += 1
                case let .text(attributes, inner):
                    let read = readingNotes(in: inner, paragraph: index, notes: &notes)

                    guard !read.text.isEmpty else { continue }

                    let centered =
                        attributes.contains("text-align:center")
                        || attributes.contains("text-align: center")
                        || isSceneBreak(read.text)

                    result.append(Paragraph(
                        id: index,
                        text: read.text,
                        isCentered: centered,
                        titleLevel: titleLevel(inside: attributes),
                        notes: read.marks,
                        scripts: read.scripts
                    ))
                    index += 1
            }
        }

        // A body with no paragraph markup at all still deserves to be readable.
        if blocks.isEmpty {
            let text = plainText(from: body)
            if !text.isEmpty { result = [ Paragraph(id: 0, text: text, isCentered: false) ] }
        }

        // A note nothing points at is not a note, and would otherwise be text the reader lost.
        let marked = Set(result.flatMap(\.notes).map(\.noteId))
        return ChapterMarkup(paragraphs: result, notes: notes.filter { marked.contains($0.key) })
    }

    /// What a marker is wrapped in while the text around it is being flattened.
    ///
    /// The flattening collapses white space and decodes entities, either of which moves a position, so
    /// the marker is fenced beforehand and its place read off afterwards. Private-use characters,
    /// because no book contains one and neither step touches them.
    private static let markerOpen: Character = "\u{E000}"
    private static let markerClose: Character = "\u{E001}"
    /// The same trick for the stretches a formula sets off the line: a fence the tag stripper leaves
    /// alone, read back out once the markup is gone.
    private static let scriptFences: [(open: Character, close: Character, place: ScriptMark.Place)] = [
        ("\u{E002}", "\u{E003}", .below),
        ("\u{E004}", "\u{E005}", .above),
    ]

    private struct ReadText {
        var text: String
        var marks: [NoteMark]
        var scripts: [ScriptMark] = []
    }

    /// One paragraph's text, with the note markers in it found and placed.
    private static func readingNotes(
        in fragment: String,
        paragraph: Int,
        notes: inout [String: BookNote]
    ) -> ReadText {
        let fragment = fencingScripts(in: fragment)
        var fenced = ""
        var ids: [String] = []
        var cursor = fragment.startIndex

        while let anchor = anchor(in: fragment, from: cursor) {
            fenced += fragment[cursor ..< anchor.range.lowerBound]
            cursor = anchor.range.upperBound

            // An anchor pointing at a note the chapter carries, or carrying its own words. Anything
            // else is an ordinary link and goes the way of the rest of the markup.
            var id: String?

            if let target = anchor.target, notes[target] != nil {
                id = target
            } else if let inline = anchor.inlineText {
                let synthetic = "inline:\(paragraph):\(ids.count)"
                notes[synthetic] = BookNote(id: synthetic, marker: "", text: inline)
                id = synthetic
            }

            guard
                let id
            else {
                fenced += fragment[anchor.range]
                continue
            }

            ids.append(id)
            fenced += String(markerOpen) + anchor.inner + String(markerClose)
        }

        fenced += fragment[cursor...]

        let flattened = plainText(from: fenced)

        guard !ids.isEmpty || flattened.contains(where: isFence) else { return ReadText(text: flattened, marks: []) }

        return placing(ids, in: flattened, notes: &notes)
    }

    private static func isFence(_ character: Character) -> Bool {
        scriptFences.contains { $0.open == character || $0.close == character }
    }

    /// Fences `<sub>` and `<sup>` before the markup is flattened, so where they stood is still known
    /// afterwards. The fences are private-use characters, which the tag stripper has no opinion about.
    private static func fencingScripts(in fragment: String) -> String {
        var result = fragment

        for fence in scriptFences {
            let name = fence.place == .below ? "sub" : "sup"

            result = result.replacingOccurrences(
                of: "<\(name)(\\s[^>]*)?>",
                with: String(fence.open),
                options: [ .regularExpression, .caseInsensitive ]
            )
            result = result.replacingOccurrences(
                of: "</\(name)\\s*>",
                with: String(fence.close),
                options: [ .regularExpression, .caseInsensitive ]
            )
        }

        return result
    }

    /// Reads the fenced markers back out of the flattened text, and records where each one landed.
    private static func placing(_ ids: [String], in text: String, notes: inout [String: BookNote]) -> ReadText {
        var result = ""
        var marks: [NoteMark] = []
        var scripts: [ScriptMark] = []
        var opened: [ScriptMark.Place: Int] = [:]
        var length = 0
        var start: Int?
        var marker = ""
        var index = 0

        for character in text {
            switch character {
                case markerOpen:
                    start = length
                    marker = ""
                case markerClose:
                    defer { index += 1 }

                    guard let from = start, index < ids.count, length > from else { break }

                    let id = ids[index]
                    marks.append(NoteMark(location: from, length: length - from, noteId: id))
                    // The marker is what names the note where it is shown, and it is only known here.
                    if let note = notes[id] {
                        notes[id] = BookNote(id: id, marker: marker, text: withoutLeading(marker, in: note.text))
                    }
                    start = nil
                default:
                    if let fence = scriptFences.first(where: { $0.open == character }) {
                        opened[fence.place] = length
                        continue
                    }

                    if let fence = scriptFences.first(where: { $0.close == character }) {
                        if let from = opened[fence.place], length > from {
                            scripts.append(ScriptMark(location: from, length: length - from, place: fence.place))
                        }

                        opened[fence.place] = nil
                        continue
                    }

                    result.append(character)
                    length += character.utf16.count
                    if start != nil { marker.append(character) }
            }
        }

        return ReadText(text: result, marks: marks, scripts: scripts)
    }

    /// A note that opens by repeating its own figure, with that figure taken off.
    ///
    /// The figure is how the note is named where it is shown, so leaving it at the head of the words
    /// as well reads as though it were the note's first word. Only an exact repeat goes: a note that
    /// happens to begin with some other number keeps it.
    private static func withoutLeading(_ marker: String, in text: String) -> String {
        let figure = marker.filter(\.isNumber)

        guard !figure.isEmpty, text.hasPrefix(figure) else { return text }

        let rest = text.dropFirst(figure.count).drop { $0.isWhitespace || $0 == "." || $0 == ")" || $0 == "]" }

        return rest.isEmpty ? text : String(rest)
    }

    private struct Anchor {
        var range: Range<String.Index>
        var inner: String
        /// The `#id` the anchor points at, less the hash.
        var target: String?
        /// The note's words, where the anchor carries them itself.
        var inlineText: String?
    }

    /// The next `<a>…</a>` at or after `cursor`, whole.
    private static func anchor(in fragment: String, from cursor: String.Index) -> Anchor? {
        var searching = cursor

        while let open = fragment.range(of: "<a", options: .caseInsensitive, range: searching ..< fragment.endIndex) {
            searching = open.upperBound

            // `<a` opens an anchor only where the tag name ends there; `<abbr` is not one.
            guard
                let next = fragment[open.upperBound...].first,
                next.isWhitespace || next == ">" || next == "/"
            else { continue }
            guard
                let openEnd = fragment.range(of: ">", range: open.upperBound ..< fragment.endIndex),
                let close = fragment.range(
                    of: "</a>",
                    options: .caseInsensitive,
                    range: openEnd.upperBound ..< fragment.endIndex
                )
            else { return nil }

            let attributes = attributes(in: fragment[open.upperBound ..< openEnd.lowerBound])
            let href = attributes["href"] ?? attributes["l:href"] ?? attributes["xlink:href"]
            let inline = attributes["title"] ?? attributes["data-note"] ?? attributes["data-title"]

            return Anchor(
                range: open.lowerBound ..< close.upperBound,
                inner: String(fragment[openEnd.upperBound ..< close.lowerBound]),
                target: href.flatMap { $0.hasPrefix("#") ? String($0.dropFirst()) : nil },
                inlineText: inline.map(decodeEntities).flatMap { $0.isEmpty ? nil : $0 }
            )
        }

        return nil
    }

    /// A tag's attributes, by lowercased name. Values keep their case, being text rather than markup.
    private static func attributes(in markup: some StringProtocol) -> [String: String] {
        var result: [String: String] = [:]
        var cursor = markup.startIndex

        while let equals = markup[cursor...].firstIndex(of: "=") {
            let name = markup[cursor ..< equals].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let rest = markup[markup.index(after: equals)...].drop { $0.isWhitespace }

            guard let quote = rest.first else { break }

            if quote == "\"" || quote == "'" {
                let value = rest.dropFirst().prefix { $0 != quote }
                result[name] = decodeEntities(in: String(value))
                cursor =
                    markup.index(rest.startIndex, offsetBy: value.count + 2, limitedBy: markup.endIndex)
                    ?? markup.endIndex
            } else {
                let value = rest.prefix { !$0.isWhitespace }
                result[name] = decodeEntities(in: String(value))
                cursor = value.endIndex
            }

            if cursor >= markup.endIndex { break }
        }

        return result
    }

    /// Every `#id` the chapter's anchors point at.
    private static func referencedIds(in html: String) -> Set<String> {
        var result: Set<String> = []
        var cursor = html.startIndex

        while let anchor = anchor(in: html, from: cursor) {
            cursor = anchor.range.upperBound

            if let target = anchor.target { result.insert(target) }
        }

        return result
    }

    private struct NoteBody {
        var id: String
        var text: String
        var range: Range<String.Index>
    }

    /// The element behind each referenced id, and the words in it.
    private static func noteBodies(among ids: Set<String>, in html: String) -> [String: NoteBody] {
        var result: [String: NoteBody] = [:]

        for id in ids {
            guard let element = element(withId: id, in: html) else { continue }

            result[id] = NoteBody(
                id: id,
                text: plainText(from: withoutLeadingAnchor(element.inner)),
                range: element.range
            )
        }

        return result
    }

    /// A note usually opens with its own marker as a link back to the text. That is navigation rather
    /// than the note, and there is nowhere to go back to from a popup.
    private static func withoutLeadingAnchor(_ inner: String) -> String {
        let start = inner.drop { $0.isWhitespace }

        guard start.hasPrefix("<a"), let anchor = anchor(in: inner, from: inner.startIndex) else { return inner }

        return String(inner[anchor.range.upperBound...])
    }

    /// The element carrying an id, from its opening bracket through its closing tag.
    private static func element(withId id: String, in html: String) -> (inner: String, range: Range<String.Index>)? {
        let escaped = NSRegularExpression.escapedPattern(for: id)
        let pattern = "<([a-zA-Z][a-zA-Z0-9]*)\\b[^>]*\\bid\\s*=\\s*[\"']\(escaped)[\"'][^>]*>"

        guard
            let match = html.range(of: pattern, options: [ .regularExpression, .caseInsensitive ]),
            let name = tagName(at: match, in: html)
        else { return nil }
        guard let close = closingTag(of: name, in: html, from: match.upperBound) else { return nil }

        return (String(html[match.upperBound ..< close.lowerBound]), match.lowerBound ..< close.upperBound)
    }

    private static func tagName(at opening: Range<String.Index>, in html: String) -> String? {
        let name = html[html.index(after: opening.lowerBound) ..< opening.upperBound]
            .prefix { $0.isLetter || $0.isNumber }

        return name.isEmpty ? nil : String(name).lowercased()
    }

    /// The closing tag that matches an already-open one, stepping over any of the same name inside it.
    private static func closingTag(of name: String, in html: String, from cursor: String.Index) -> HTMLRange? {
        var depth = 0
        var searching = cursor

        while searching < html.endIndex {
            let opening = html.range(of: "<\(name)", options: .caseInsensitive, range: searching ..< html.endIndex)
            let closing = html.range(of: "</\(name)", options: .caseInsensitive, range: searching ..< html.endIndex)

            guard let closing else { return nil }

            if let opening, opening.lowerBound < closing.lowerBound {
                depth += 1
                searching = opening.upperBound
                continue
            }

            guard
                depth > 0
            else {
                let stop = html.range(of: ">", range: closing.upperBound ..< html.endIndex)
                return closing.lowerBound ..< (stop?.upperBound ?? html.endIndex)
            }

            depth -= 1
            searching = closing.upperBound
        }

        return nil
    }

    /// Cuts the note bodies out of the chapter, back to front so the ranges hold.
    private static func removing(_ ranges: some Sequence<Range<String.Index>>, from html: String) -> String {
        var result = html

        for range in ranges.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            result.replaceSubrange(range, with: "")
        }

        return result
    }
}
