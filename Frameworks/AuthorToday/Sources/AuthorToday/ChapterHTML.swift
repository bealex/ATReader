//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// Turns the HTML a chapter arrives in into flat paragraphs a reader view can lay out.
///
/// Chapter bodies use a small, predictable subset — `<p>`, `<br>`, `<span>`, emphasis and the odd `<img>` —
/// so a targeted pass beats pulling in a full HTML stack, and it keeps the work off the main actor.
public enum ChapterHTML {
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

        public init(id: Int, text: String, isCentered: Bool, imageSource: String? = nil) {
            self.id = id
            self.text = text
            self.isCentered = isCentered
            self.imageSource = imageSource
        }

        public var isImage: Bool { imageSource != nil }
    }

    public static func paragraphs(from html: String) -> [Paragraph] {
        var result: [Paragraph] = []
        var index = 0
        let blocks = blocks(in: html)

        for block in blocks {
            switch block {
                case let .picture(source):
                    result.append(Paragraph(id: index, text: "", isCentered: true, imageSource: source))
                    index += 1
                case let .text(attributes, inner):
                    let centered =
                        attributes.contains("text-align:center")
                        || attributes.contains("text-align: center")
                    let text = plainText(from: inner)

                    guard !text.isEmpty else { continue }

                    result.append(Paragraph(id: index, text: text, isCentered: centered))
                    index += 1
            }
        }

        // A body with no paragraph markup at all still deserves to be readable.
        if blocks.isEmpty {
            let text = plainText(from: html)
            if !text.isEmpty { result = [ Paragraph(id: 0, text: text, isCentered: false) ] }
        }

        return result
    }

    private enum Block {
        case text(attributes: String, inner: String)
        case picture(String)
    }

    /// Walks the body once, taking paragraphs and pictures in the order they stand in it.
    private static func blocks(in html: String) -> [Block] {
        var blocks: [Block] = []
        var cursor = html.startIndex

        while cursor < html.endIndex {
            let paragraph = html.range(of: "<p", options: .caseInsensitive, range: cursor ..< html.endIndex)
            let picture = html.range(of: "<img", options: .caseInsensitive, range: cursor ..< html.endIndex)

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
}

extension ChapterText {
    /// The chapter body, ready to lay out.
    public var paragraphs: [ChapterHTML.Paragraph] { ChapterHTML.paragraphs(from: html) }
}
