//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// A tolerant reader for the XML an EPUB is made of.
///
/// `XMLParser` refuses a document naming an entity no DTD declared, which is most of the XHTML
/// publishers ship, and it gives up on the first mismatched tag. So the markup is scanned rather than
/// validated: nothing here throws, and what it can't make sense of it steps over.
///
/// A tree rather than a walk, because the documents are one chapter each and everything read from one
/// is decided by where an element stands rather than by the order it arrives in.
enum Markup {
    /// One element, or a run of text where ``text`` is set.
    final class Node {
        /// The element's own name, folded and with any prefix dropped, so `dc:title` reads as `title`.
        let name: String
        /// By folded name. A prefixed attribute answers to its local name as well, where nothing else
        /// has claimed it, which is what makes `xlink:href` and `href` one lookup.
        let attributes: [String: String]
        let text: String?

        private(set) var children: [Node] = []

        init(name: String, attributes: [String: String] = [:], text: String? = nil) {
            self.name = name
            self.attributes = attributes
            self.text = text
        }

        func add(_ child: Node) { children.append(child) }

        var isText: Bool { text != nil }

        var elements: [Node] { children.filter { !$0.isText } }

        /// Every element of this name directly inside this one.
        func children(_ name: String) -> [Node] { children.filter { $0.name == name } }

        /// The first element of this name anywhere beneath, depth first.
        func first(_ name: String) -> Node? {
            for child in children where !child.isText {
                if child.name == name { return child }

                if let found = child.first(name) { return found }
            }

            return nil
        }

        /// Every element of this name anywhere beneath, in the order they stand.
        func all(_ name: String) -> [Node] {
            var found: [Node] = []

            collect(name, into: &found)
            return found
        }

        private func collect(_ name: String, into found: inout [Node]) {
            for child in children where !child.isText {
                if child.name == name { found.append(child) }

                child.collect(name, into: &found)
            }
        }

        /// The words under this element, every tag beneath it dropped and the white space collapsed.
        var words: String {
            var result = ""

            gather(into: &result)
            return result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private func gather(into result: inout String) {
            if let text {
                result += text
                return
            }

            for child in children { child.gather(into: &result) }
        }

        /// True where this element carries the given word in its `class` or its `epub:type`.
        func isMarked(_ word: String) -> Bool {
            let marks = (attributes["class"] ?? "") + " " + (attributes["type"] ?? "")

            return marks.lowercased().split(whereSeparator: \.isWhitespace).contains(Substring(word))
        }
    }

    /// The document as one root element holding everything the markup declared.
    static func parse(_ text: String) -> Node {
        var scanner = Scanner(Array(text.unicodeScalars))

        return scanner.document()
    }

    /// Elements that never hold anything, so an opening tag is the whole of them.
    private static let voids: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "param", "source",
        "track", "wbr",
    ]

    /// `<meta>` is not among them. It closes itself everywhere this reads one, and an EPUB's package
    /// states half of what it knows as the text inside a `<meta>` rather than as an attribute on it.

    /// Elements whose contents are not markup and are dropped whole.
    private static let opaque: Set<String> = [ "script", "style" ]

    /// Elements a file may leave open, closed by the next one of their own kind.
    private static let loose: Set<String> = [ "p", "li", "dd", "dt", "td", "th", "tr", "option" ]

    private struct Scanner {
        private let source: [Unicode.Scalar]
        private var cursor = 0

        init(_ source: [Unicode.Scalar]) { self.source = source }

        mutating func document() -> Node {
            let root = Node(name: "")
            var stack = [ root ]

            while cursor < source.count {
                guard
                    let mark = seek("<")
                else {
                    append(text(from: cursor, to: source.count), to: stack)
                    break
                }

                append(text(from: cursor, to: mark), to: stack)
                cursor = mark

                if skippedAside() { continue }

                if reads("/", at: 1) {
                    close(&stack)
                } else {
                    open(&stack)
                }
            }

            return root
        }

        // MARK: - The pieces of a document

        /// A comment, a declaration or a processing instruction, none of which the tree keeps.
        private mutating func skippedAside() -> Bool {
            if matches("<!--") {
                cursor = (seek("-->").map { $0 + 3 }) ?? source.count
                return true
            }

            guard reads("!", at: 1) || reads("?", at: 1) else { return false }

            // A doctype's internal subset carries brackets of its own, and the `>` that closes it
            // stands after them rather than at the first one.
            if matches("<!DOCTYPE"), let bracket = seek("["), bracket < (seek(">") ?? source.count) {
                cursor = (seek("]", from: bracket).flatMap { seek(">", from: $0) }.map { $0 + 1 }) ?? source.count
                return true
            }

            cursor = (seek(">").map { $0 + 1 }) ?? source.count
            return true
        }

        private mutating func close(_ stack: inout [Node]) {
            let start = cursor + 2
            let name = readName(from: start).name

            cursor = (seek(">", from: start).map { $0 + 1 }) ?? source.count

            guard let depth = stack.lastIndex(where: { $0.name == name }), depth > 0 else { return }

            stack.removeSubrange(depth...)
        }

        private mutating func open(_ stack: inout [Node]) {
            let start = cursor + 1
            let read = readName(from: start)

            guard
                !read.name.isEmpty
            else {
                cursor = start
                return
            }

            let name = read.name
            var attributes: [String: String] = [:]
            var index = read.end
            let selfClosing = readAttributes(from: &index, into: &attributes)

            cursor = index

            if Markup.opaque.contains(name) {
                cursor = skipToClose(of: name)
                return
            }

            // A file that leaves one of these open means it to end where the next one begins.
            if Markup.loose.contains(name), stack.last?.name == name { stack.removeLast() }

            let node = Node(name: name, attributes: attributes)

            stack.last?.add(node)

            guard !selfClosing, !Markup.voids.contains(name) else { return }

            stack.append(node)
        }

        /// Everything up to the matching close of an element whose contents are not markup.
        private mutating func skipToClose(of name: String) -> Int {
            var index = cursor

            while let mark = seek("<", from: index) {
                guard
                    mark + 2 < source.count,
                    source[mark + 1] == "/"
                else {
                    index = mark + 1
                    continue
                }
                guard
                    readName(from: mark + 2).name == name
                else {
                    index = mark + 1
                    continue
                }

                return (seek(">", from: mark).map { $0 + 1 }) ?? source.count
            }

            return source.count
        }

        // MARK: - Reading a tag

        /// A tag's name, folded and with any prefix dropped, and where it ends in the source.
        ///
        /// Both, because folding a name changes its length: `dc:title` reads as `title` and the tag it
        /// opens is three scalars longer than the name it gives.
        private func readName(from start: Int) -> (name: String, end: Int) {
            var index = start

            while index < source.count, isNameScalar(source[index]) { index += 1 }

            let whole = string(from: start, to: index).lowercased()

            return (whole.split(separator: ":").last.map(String.init) ?? whole, index)
        }

        /// Reads a tag's attributes up to its closing bracket. Reports whether the tag closed itself.
        private func readAttributes(from index: inout Int, into attributes: inout [String: String]) -> Bool {
            var selfClosing = false

            while index < source.count {
                while index < source.count, isSpace(source[index]) { index += 1 }

                guard index < source.count else { break }

                if source[index] == ">" {
                    index += 1
                    break
                }

                if source[index] == "/" {
                    selfClosing = true
                    index += 1
                    continue
                }

                guard let read = readAttribute(from: &index) else { continue }

                let key = read.key
                let decoded = read.value

                attributes[key] = decoded

                // A prefixed attribute answers to its local name too, so `xlink:href` reads as `href`.
                if let local = key.split(separator: ":").last.map(String.init), local != key {
                    attributes[local] = attributes[local] ?? decoded
                }
            }

            return selfClosing
        }

        /// One attribute, or nothing where what stood there was not a name.
        private func readAttribute(from index: inout Int) -> (key: String, value: String)? {
            let start = index

            while index < source.count, isNameScalar(source[index]) { index += 1 }

            guard
                index > start
            else {
                index += 1
                return nil
            }

            let key = string(from: start, to: index).lowercased()

            while index < source.count, isSpace(source[index]) { index += 1 }

            guard index < source.count, source[index] == "=" else { return (key, "") }

            index += 1

            while index < source.count, isSpace(source[index]) { index += 1 }

            return (key, Entities.decoded(readValue(from: &index)))
        }

        private func readValue(from index: inout Int) -> String {
            guard index < source.count else { return "" }

            let quote = source[index]

            guard
                quote == "\"" || quote == "'"
            else {
                let start = index

                while index < source.count, !isSpace(source[index]), source[index] != ">" { index += 1 }

                return string(from: start, to: index)
            }

            index += 1
            let start = index

            while index < source.count, source[index] != quote { index += 1 }

            let value = string(from: start, to: index)

            if index < source.count { index += 1 }

            return value
        }

        // MARK: - Reading text

        private func text(from start: Int, to end: Int) -> String? {
            guard end > start else { return nil }

            var result = ""
            var index = start

            while index < end {
                // A CDATA section is text whatever it holds, and its markup is not markup.
                guard
                    source[index] == "<",
                    matches("<![CDATA[", from: index)
                else {
                    result.unicodeScalars.append(source[index])
                    index += 1
                    continue
                }

                let body = index + 9
                let stop = seek("]]>", from: body) ?? end

                result += string(from: body, to: min(stop, end))
                index = min(stop + 3, end)
            }

            return result.isEmpty ? nil : Entities.decoded(result)
        }

        private func append(_ text: String?, to stack: [Node]) {
            guard let text, !text.isEmpty else { return }

            stack.last?.add(Node(name: "", text: text))
        }

        // MARK: - Looking about

        private func reads(_ scalar: Unicode.Scalar, at offset: Int) -> Bool {
            cursor + offset < source.count && source[cursor + offset] == scalar
        }

        /// Whether the source reads as this word here, a doctype's own case disregarded.
        private func matches(_ word: String, from start: Int? = nil) -> Bool {
            let start = start ?? cursor
            let wanted = Array(word.unicodeScalars)

            guard start + wanted.count <= source.count else { return false }

            for (offset, scalar) in wanted.enumerated()
            where Self.folded(source[start + offset]) != Self.folded(scalar) {
                return false
            }

            return true
        }

        private static func folded(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
            guard scalar.value >= 65, scalar.value <= 90 else { return scalar }

            return Unicode.Scalar(scalar.value + 32) ?? scalar
        }

        private func seek(_ word: String, from start: Int? = nil) -> Int? {
            let wanted = Array(word.unicodeScalars)
            var index = start ?? cursor

            while index + wanted.count <= source.count {
                if source[index] == wanted[0], matches(word, from: index) { return index }

                index += 1
            }

            return nil
        }

        private func string(from start: Int, to end: Int) -> String {
            guard end > start, start >= 0, end <= source.count else { return "" }

            return String(String.UnicodeScalarView(source[start ..< end]))
        }

        private func isSpace(_ scalar: Unicode.Scalar) -> Bool {
            scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r"
        }

        private func isNameScalar(_ scalar: Unicode.Scalar) -> Bool {
            if scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" { return false }

            return scalar != "=" && scalar != ">" && scalar != "/" && scalar != "\"" && scalar != "'" && scalar != "<"
        }
    }
}
