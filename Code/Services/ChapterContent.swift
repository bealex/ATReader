//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import BookKit
import Foundation
import NaturalLanguage

/// Everything that makes a ``ChapterContent``. Moves to BookRenderer with the typesetter.
extension ChapterContent {
    static func prepare(html: String) async -> ChapterContent {
        await Task.detached(priority: .userInitiated) {
            let paragraphs = BookHTML.paragraphs(from: html)
            let language = Self.language(of: paragraphs)
            let bound = paragraphs.map { paragraph in
                Paragraph(
                    id: paragraph.id,
                    // The dashes are put right first: binding reads them, and so does the layout when
                    // it decides which lines open on the dash of speech.
                    text: Typography.bound(Typography.dashes(paragraph.text, language: language), language: language),
                    isCentered: paragraph.isCentered,
                    imageSource: paragraph.imageSource
                )
            }
            let hyphenated = bound.map { paragraph in
                Paragraph(
                    id: paragraph.id,
                    text: Typography.hyphenated(paragraph.text, language: language),
                    isCentered: paragraph.isCentered,
                    imageSource: paragraph.imageSource
                )
            }
            return ChapterContent(paragraphs: bound, hyphenated: hyphenated, language: language)
        }.value
    }

    private static func language(of paragraphs: [Paragraph]) -> String? {
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
