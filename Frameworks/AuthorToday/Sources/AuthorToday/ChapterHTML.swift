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
    /// One laid-out block of a chapter.
    public struct Paragraph: Codable, Sendable, Identifiable, Hashable {
        public let id: Int
        public let text: String
        /// Author-centred lines (scene breaks, epigraphs) carry a `text-align: center` style.
        public let isCentered: Bool

        public init(id: Int, text: String, isCentered: Bool) {
            self.id = id
            self.text = text
            self.isCentered = isCentered
        }
    }

    public static func paragraphs(from html: String) -> [Paragraph] {
        var result: [Paragraph] = []
        var index = 0

        for block in blocks(in: html) {
            let centered =
                block.attributes.contains("text-align:center")
                || block.attributes.contains("text-align: center")
            let text = plainText(from: block.inner)

            guard !text.isEmpty else { continue }

            result.append(Paragraph(id: index, text: text, isCentered: centered))
            index += 1
        }

        // A body with no paragraph markup at all still deserves to be readable.
        if result.isEmpty {
            let text = plainText(from: html)
            if !text.isEmpty { result = [ Paragraph(id: 0, text: text, isCentered: false) ] }
        }

        return result
    }

    private struct Block {
        let attributes: String
        let inner: String
    }

    private static func blocks(in html: String) -> [Block] {
        var blocks: [Block] = []
        var cursor = html.startIndex

        while let open = html.range(of: "<p", options: .caseInsensitive, range: cursor ..< html.endIndex) {
            guard let openEnd = html.range(of: ">", range: open.upperBound ..< html.endIndex) else { break }

            let attributes = String(html[open.upperBound ..< openEnd.lowerBound])
                .replacingOccurrences(of: " ", with: "")
                .lowercased()
            let closeRange = html.range(
                of: "</p>",
                options: .caseInsensitive,
                range: openEnd.upperBound ..< html.endIndex
            )
            let inner = String(html[openEnd.upperBound ..< (closeRange?.lowerBound ?? html.endIndex)])

            blocks.append(Block(attributes: attributes, inner: inner))
            cursor = closeRange?.upperBound ?? html.endIndex
        }

        return blocks
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
