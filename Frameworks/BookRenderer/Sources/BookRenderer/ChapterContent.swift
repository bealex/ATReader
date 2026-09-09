//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Foundation
import NaturalLanguage

/// Everything that makes a ``ChapterContent``. Moves to BookRenderer with the typesetter.
public extension ChapterContent {
    public static func prepare(html: String) async -> ChapterContent {
        await Task.detached(priority: .userInitiated) {
            let chapter = BookHTML.chapter(from: html)
            let paragraphs = chapter.paragraphs
            let language = Self.language(of: paragraphs)
            let bound = paragraphs.map { paragraph in
                Self.setting(
                    paragraph,
                    // The dashes are put right first: binding reads them, and so does the layout when
                    // it decides which lines open on the dash of speech.
                    as: Typography.bound(Typography.dashes(paragraph.text, language: language), language: language)
                )
            }
            let hyphenated = bound.map { paragraph in
                Self.setting(paragraph, as: Typography.hyphenated(paragraph.text, language: language))
            }
            return ChapterContent(paragraphs: bound, hyphenated: hyphenated, language: language, notes: chapter.notes)
        }.value
    }

    /// One paragraph as the typesetter left it, with its note markers put back where they now stand.
    private static func setting(_ paragraph: Paragraph, as text: String) -> Paragraph {
        Paragraph(
            id: paragraph.id,
            text: text,
            isCentered: paragraph.isCentered,
            imageSource: paragraph.imageSource,
            notes: placed(paragraph.notes, in: text)
        )
    }

    /// Where a paragraph's note markers land once the typesetter has been through its text.
    ///
    /// Binding and hyphenation both put characters in — word joiners and soft hyphens — so a mark
    /// counted straight through would drift a little further with every one of them. Counting only
    /// the characters the text arrived with puts each marker back where it was.
    private static func placed(_ marks: [NoteMark], in text: String) -> [NoteMark] {
        guard !marks.isEmpty else { return [] }

        let string = text as NSString
        var positions: [Int] = []

        positions.reserveCapacity(string.length)

        for index in 0 ..< string.length {
            let unit = string.character(at: index)
            let isFormat = Unicode.Scalar(unit).map { $0.properties.generalCategory == .format } ?? false

            if !isFormat { positions.append(index) }
        }

        return marks.compactMap { mark in
            let last = mark.location + mark.length - 1

            guard mark.location < positions.count, last < positions.count, last >= mark.location else { return nil }

            let start = positions[mark.location]
            return NoteMark(location: start, length: positions[last] + 1 - start, noteId: mark.noteId)
        }
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
    public static func isMostlyCyrillic(_ text: some StringProtocol) -> Bool {
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
