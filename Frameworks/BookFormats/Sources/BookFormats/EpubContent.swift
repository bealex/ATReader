//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// One EPUB content document reduced to the markup a chapter body is written in.
///
/// The whole of the reduction is here. An EPUB's XHTML is a presentational format where the same page
/// has fifty encodings, and what this keeps is what the reader can set: blocks of text, the headings
/// that divide them, emphasis, the pictures, the notes, and which way round the whole thing reads.
/// Everything else, the styling above all, belongs to whoever is reading rather than to the publisher.
struct EpubContent {
    var html = ""
    /// Characters of text, which is what a book's reading progress is weighed in.
    var textLength = 0
    /// Where in the archive each picture the document points at stands.
    var pictures: Set<String> = []
    /// The notes this document points at, under the name the whole book knows them by.
    var references: Set<String> = []
    /// Every place in the book this document points at, its notes among them.
    var links: Set<String> = []
    /// Text this document holds under an id, which is what a note pointing at it will want.
    var marked: [String: String] = [:]
    /// The document's own opening heading, for a book whose navigation named nothing.
    var heading: String?

    /// What the book knows a place inside it by, wherever in the book the reference is written.
    ///
    /// Ids repeat across an EPUB's files, so the document is folded into the name along with the id.
    static func reference(path: String, fragment: String) -> String {
        "n\(String(hash(of: path + "#" + fragment), radix: 36))"
    }

    /// A hash that answers the same on every run, so a chapter's stored markup keeps meaning.
    private static func hash(of text: String) -> UInt64 {
        var value: UInt64 = 0xCBF2_9CE4_8422_2325

        for byte in text.utf8 {
            value = (value ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }

        return value
    }

    // MARK: - Reading one

    static func read(
        _ document: Markup.Node,
        path: String,
        styles: EpubStyles,
        readsRightToLeft: Bool,
        divisions: Set<String> = [],
        anchors: Set<String> = []
    ) -> EpubContent {
        var reducer = Reducer(
            path: path,
            base: (path as NSString).deletingLastPathComponent,
            styles: styles,
            readsRightToLeft: readsRightToLeft,
            divisions: divisions,
            anchors: anchors
        )

        reducer.read(document.first("body") ?? document)
        return reducer.content
    }

    /// Walks one document, keeping what the reader can set and dropping the rest.
    ///
    /// Never crosses an isolation boundary: made, driven and read inside ``read(_:path:styles:)``,
    /// which is synchronous, so it needs no `Sendable` of its own.
    private struct Reducer {
        let path: String
        let base: String
        let styles: EpubStyles
        let readsRightToLeft: Bool
        /// The ids the book's own navigation points at, which are where its chapters begin.
        let divisions: Set<String>
        /// The places anything in the book links to, which are the only ones worth marking.
        let anchors: Set<String>

        private(set) var content = EpubContent()

        /// How a block stands: what the elements around it have said about it so far.
        private struct Frame {
            var isCentered = false
            var titleLevel: Int?
            var listLevel = 0
            var isRightToLeft: Bool
        }

        /// The text of the block being filled, as markup and as words.
        ///
        /// Both, because what the block is worth is decided by the words while what is written down is
        /// the markup, and emphasis puts tags in one that the other must not count.
        private var buffer = ""
        private var plain = ""
        /// The mark an item of a list opens with, held until the block that will carry it is closed.
        private var marker: String?
        /// A chapter starts at the next block written down. Held rather than acted on at once, because
        /// what the navigation points at is as often the element wrapping a heading as the heading.
        private var division: String?
        /// A place something in the book points at, held until the block that will carry it is closed.
        private var landing: String?

        mutating func read(_ body: Markup.Node) {
            var frame = Frame(isRightToLeft: readsRightToLeft)

            frame.isRightToLeft = frame.isRightToLeft || isRightToLeft(body)
            walk(children: body, in: frame)
            flush(frame)
        }

        // MARK: - Walking the document

        private mutating func walk(_ node: Markup.Node, in frame: Frame) {
            if let text = node.text { return append(text) }

            guard !Self.ignored.contains(node.name) else { return }

            if let tag = Self.emphasisTag(of: node.name) { return emphasis(tag, node, in: frame) }

            switch node.name {
                case "br":
                    buffer += "<br>"
                    plain += " "
                case "hr":
                    flush(frame)
                    content.html += line("* * *", in: centred(frame))
                case "img", "image":
                    picture(node, in: frame)
                case "ul", "ol", "dl":
                    list(node, in: frame)
                case "a":
                    divide(node)
                    anchor(node, in: frame)
                case _ where Self.inline.contains(node.name):
                    divide(node)
                    walk(children: node, in: inheriting(node, in: frame))
                default:
                    block(node, in: frame)
            }
        }

        private mutating func walk(children node: Markup.Node, in frame: Frame) {
            for child in node.children { walk(child, in: frame) }
        }

        /// A block of the document: everything standing in it is one piece of text of its own.
        private mutating func block(_ node: Markup.Node, in frame: Frame) {
            flush(frame)
            divide(node)
            remember(node)

            // A note set beside the text it belongs to is a note rather than a paragraph of the
            // chapter, and is written out under whichever chapters point at it instead.
            guard !isNote(node) else { return }

            var inner = inheriting(node, in: frame)

            inner.titleLevel = Self.titleLevel(of: node.name) ?? frame.titleLevel

            walk(children: node, in: inner)
            flush(inner)
        }

        /// A list, whose items are blocks that open with a mark of their own.
        ///
        /// The mark goes into the text rather than beside it: a reading position counts the characters
        /// of a chapter, so anything the page shows has to be among them.
        private mutating func list(_ node: Markup.Node, in frame: Frame) {
            flush(frame)
            divide(node)

            var inner = inheriting(node, in: frame)
            let isOrdered = node.name == "ol"
            var ordinal = node.attributes["start"].flatMap { Int($0) } ?? 1

            inner.listLevel = frame.listLevel + 1

            for item in node.children where !item.isText {
                guard
                    item.name == "li" || item.name == "dd" || item.name == "dt"
                else {
                    walk(item, in: inner)
                    continue
                }

                flush(inner)
                remember(item)
                marker = isOrdered ? "\(ordinal). " : "• "
                ordinal += 1

                walk(children: item, in: inheriting(item, in: inner))
                flush(inner)
            }

            marker = nil
        }

        // MARK: - What stands inside a block

        /// The tag a stretch of text is written with, where this element sets one apart.
        private static func emphasisTag(of name: String) -> String? {
            switch name {
                case "em", "i", "cite", "dfn", "var": "i"
                case "strong", "b": "b"
                case "sub": "sub"
                case "sup": "sup"
                default: nil
            }
        }

        private mutating func emphasis(_ tag: String, _ node: Markup.Node, in frame: Frame) {
            buffer += "<\(tag)>"
            walk(children: node, in: frame)
            buffer += "</\(tag)>"
        }

        /// A link, which is a note's marker where it points at a note and text where it doesn't.
        ///
        /// Whether it is one can't be settled until its own words are read: a marker is a figure or a
        /// star, and a link saying "see chapter three" is navigation this reader has nowhere to take.
        private mutating func anchor(_ node: Markup.Node, in frame: Frame) {
            let href = node.attributes["href"] ?? ""
            // Empty halves kept: a link into the document it stands in writes no path at all, and a
            // split that dropped the empty half would leave the fragment looking like one.
            let pieces = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)

            guard
                !href.contains("://"),
                !href.hasPrefix("mailto:"),
                pieces.count == 2,
                !pieces[1].isEmpty
            else { return walk(children: node, in: frame) }

            let target = pieces[0].isEmpty ? path : EpubPackage.resolve(String(pieces[0]), against: base)
            let name = EpubContent.reference(path: target, fragment: String(pieces[1]))
            let start = buffer.endIndex
            let before = plain.count

            walk(children: node, in: frame)

            guard buffer.endIndex > start else { return }

            buffer.replaceSubrange(start..., with: "<a href=\"#\(name)\">\(buffer[start...])</a>")
            content.links.insert(name)

            // A link of a few characters is a note's marker. Anything longer is a place in the book,
            // and the reader follows it rather than showing it in an aside.
            if node.isMarked("noteref") || plain.count - before <= Self.longestMarker {
                content.references.insert(name)
            }
        }

        private mutating func picture(_ node: Markup.Node, in frame: Frame) {
            let source = node.attributes["src"] ?? node.attributes["href"] ?? ""

            guard !source.isEmpty, !source.hasPrefix("data:"), !source.contains("://") else { return }

            flush(frame)
            divide(node)

            let resolved = EpubPackage.resolve(source, against: base)

            content.pictures.insert(resolved)
            content.html += "<img\(opening()) src=\"\(Self.escaped(resolved))\">"
        }

        private mutating func append(_ text: String) {
            buffer += Self.escaped(text)
            plain += text
        }

        // MARK: - Closing a block

        /// Writes down what has been gathered, unless it came to nothing.
        private mutating func flush(_ frame: Frame) {
            defer {
                buffer = ""
                plain = ""
                marker = nil
            }

            let words = plain.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmed

            guard !words.isEmpty else { return }

            let opening = marker ?? ""

            content.html += line(opening + buffer.trimmed, in: frame)

            content.textLength += opening.count + words.count

            if frame.titleLevel != nil, content.heading == nil { content.heading = opening + words }
        }

        /// One block written the way a chapter body writes one.
        private mutating func line(_ body: String, in frame: Frame) -> String {
            let level = frame.titleLevel

            guard level == nil else { return "<h\(level ?? 1)\(opening())\(direction(frame))>\(body)</h\(level ?? 1)>" }

            var attributes = opening() + direction(frame)

            if frame.isCentered { attributes += " style=\"text-align:center\"" }

            if frame.listLevel > 0 { attributes += " data-list=\"\(frame.listLevel)\"" }

            return "<p\(attributes)>\(body)</p>"
        }

        private func direction(_ frame: Frame) -> String { frame.isRightToLeft ? " dir=\"rtl\"" : "" }

        /// Notes on the block being written that a chapter starts at it, and gives the mark up.
        private mutating func opening() -> String {
            var written = ""

            if let division {
                self.division = nil
                written += " data-cut=\"\(Self.escaped(division))\""
            }

            if let landing {
                self.landing = nil
                written += " data-anchor=\"\(Self.escaped(landing))\""
            }

            return written.isEmpty ? "" : written + " "
        }

        /// Remembers that the navigation names this element as the head of a chapter.
        private mutating func divide(_ node: Markup.Node) {
            guard let id = node.attributes["id"] else { return }

            if divisions.contains(id) { division = id }

            let name = EpubContent.reference(path: path, fragment: id)

            if anchors.contains(name) { landing = name }
        }

        private func centred(_ frame: Frame) -> Frame {
            var centred = frame

            centred.isCentered = true
            centred.titleLevel = nil
            centred.listLevel = 0
            return centred
        }

        // MARK: - What an element says about itself

        /// A frame carrying whatever this element adds to the one around it.
        private func inheriting(_ node: Markup.Node, in frame: Frame) -> Frame {
            var inner = frame

            inner.isCentered = frame.isCentered || isCentered(node)
            inner.isRightToLeft = frame.isRightToLeft || isRightToLeft(node)

            if node.attributes["dir"] == "ltr" { inner.isRightToLeft = false }

            return inner
        }

        private func isCentered(_ node: Markup.Node) -> Bool {
            if node.name == "center" { return true }

            let style = (node.attributes["style"] ?? "").lowercased().replacingOccurrences(of: " ", with: "")

            if style.contains("text-align:center") { return true }

            return classes(of: node).contains(where: styles.centered.contains)
        }

        private func isRightToLeft(_ node: Markup.Node) -> Bool {
            if node.attributes["dir"] == "rtl" { return true }

            return classes(of: node).contains(where: styles.rightToLeft.contains)
        }

        private func classes(of node: Markup.Node) -> [String] {
            (node.attributes["class"] ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        }

        /// Keeps a short block standing under an id, since a note somewhere in the book may be it.
        ///
        /// Short, because a note is a sentence or two: an id on the element wrapping a whole chapter is
        /// the book's own scaffolding rather than anything a marker points at.
        private mutating func remember(_ node: Markup.Node) {
            guard let id = node.attributes["id"]?.nilWhenEmpty else { return }

            let words = node.words

            guard !words.isEmpty, words.count <= Self.longestNote else { return }

            content.marked[EpubContent.reference(path: path, fragment: id)] = words
        }

        /// True where an element is a note rather than a piece of the chapter it stands in.
        private func isNote(_ node: Markup.Node) -> Bool {
            guard node.attributes["id"] != nil else { return false }

            return Self.noteKinds.contains { node.isMarked($0) }
        }

        private static func titleLevel(of name: String) -> Int? {
            guard name.count == 2, name.hasPrefix("h"), let level = Int(name.dropFirst()) else { return nil }

            return (1 ... 6).contains(level) ? level : nil
        }

        private static func escaped(_ text: String) -> String {
            text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }

        /// What a book calls the thing a marker points at.
        private static let noteKinds = [ "footnote", "endnote", "rearnote", "note" ]

        /// How long a link's own words may run and still read as a note's marker rather than as a
        /// cross-reference. A marker is a figure, a star or a bracketed figure.
        private static let longestMarker = 8
        /// How long a block may run and still be a note. Past this it is a piece of the book.
        private static let longestNote = 2000

        /// Elements whose contents are not the book's text.
        private static let ignored: Set<String> = [
            "head", "script", "style", "title", "meta", "link", "nav", "audio", "video", "iframe",
            // The reading beside a Japanese word, which the base text already carries.
            "rt", "rp", "rtc",
        ]

        /// Elements that stand inside a block rather than making one of their own.
        private static let inline: Set<String> = [
            "span", "small", "u", "s", "strike", "del", "ins", "abbr", "acronym", "q", "ruby", "rb",
            "time", "bdi", "bdo", "mark", "big", "font", "tt", "code", "kbd", "samp", "label", "nobr",
            "wbr", "a", "select", "button",
        ]
    }
}
