//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import Foundation
import NaturalLanguage

/// A chapter's text, parsed and ready to lay out.
struct ChapterContent: Codable, Sendable {
    var paragraphs: [ChapterHTML.Paragraph]
    /// The same paragraphs with every break point the language's dictionary allows already marked.
    /// Justified setting uses these; working them out costs about as much as laying the chapter out,
    /// so it happens once here rather than on every re-pagination.
    var hyphenated: [ChapterHTML.Paragraph]
    /// The language the chapter is written in, which decides which hyphenation dictionary lays it out
    /// and how it is shaped.
    var language: String?

    var isEmpty: Bool { paragraphs.isEmpty }

    /// Every picture the chapter points at, in the order it stands in the text.
    var imageSources: [String] { paragraphs.compactMap(\.imageSource) }

    /// Parses a chapter body, works out its language and binds the words its typography won't let a
    /// line break between, all away from the main actor.
    static func prepare(html: String) async -> ChapterContent {
        await Task.detached(priority: .userInitiated) {
            let paragraphs = ChapterHTML.paragraphs(from: html)
            let language = Self.language(of: paragraphs)
            let bound = paragraphs.map { paragraph in
                ChapterHTML.Paragraph(
                    id: paragraph.id,
                    // The dashes are put right first: binding reads them, and so does the layout when
                    // it decides which lines open on the dash of speech.
                    text: Typography.bound(Typography.dashes(paragraph.text, language: language), language: language),
                    isCentered: paragraph.isCentered,
                    imageSource: paragraph.imageSource
                )
            }
            let hyphenated = bound.map { paragraph in
                ChapterHTML.Paragraph(
                    id: paragraph.id,
                    text: Typography.hyphenated(paragraph.text, language: language),
                    isCentered: paragraph.isCentered,
                    imageSource: paragraph.imageSource
                )
            }
            return ChapterContent(paragraphs: bound, hyphenated: hyphenated, language: language)
        }.value
    }

    private static func language(of paragraphs: [ChapterHTML.Paragraph]) -> String? {
        let sample = paragraphs.prefix(8).map(\.text).joined(separator: " ").prefix(1200)

        guard !sample.isEmpty else { return nil }

        // Cyrillic is read as Russian: the typography has rules for Russian and English and none for
        // the recogniser's other Cyrillic answers, which it reaches for on a short or odd sample.
        if isMostlyCyrillic(sample) { return "ru" }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(sample))
        return recognizer.dominantLanguage?.rawValue
    }

    /// True where the sample carries more Cyrillic letters than Latin ones.
    static func isMostlyCyrillic(_ text: some StringProtocol) -> Bool {
        var cyrillic = 0
        var latin = 0

        for scalar in text.unicodeScalars {
            if (0x0400 ... 0x04FF).contains(scalar.value) {
                cyrillic += 1
            } else if scalar.isASCII, CharacterSet.letters.contains(scalar) {
                latin += 1
            }
        }

        return cyrillic > latin
    }
}
