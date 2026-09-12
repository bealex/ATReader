//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Foundation
import NaturalLanguage

/// Everything that makes a ``ChapterContent``. Moves to BookRenderer with the typesetter.
public extension ChapterContent {
    static func prepare(html: String) async -> ChapterContent {
        await Task.detached(priority: .userInitiated) {
            let chapter = BookHTML.chapter(from: html)
            let paragraphs = chapter.paragraphs
            let language = Self.language(of: paragraphs)
            // The dashes are put right first: binding reads them, and so does the layout when it decides
            // which lines open on the dash of speech.
            let texts = paragraphs.map { paragraph in
                Typography.bound(Typography.dashes(paragraph.text, language: language), language: language)
            }
            // Each setting places its markers from the source marks, which count the text as it arrived.
            let bound = zip(paragraphs, texts).map { Self.setting($0, as: $1) }
            let hyphenated = zip(paragraphs, texts).map { paragraph, text in
                Self.setting(paragraph, as: Typography.hyphenated(text, language: language))
            }
            return ChapterContent(paragraphs: bound, hyphenated: hyphenated, language: language, notes: chapter.notes)
        }.value
    }

    /// One paragraph as the typesetter left it, with everything it points at put back where it stands.
    private static func setting(_ paragraph: Paragraph, as text: String) -> Paragraph {
        let places = positions(in: text)

        return Paragraph(
            id: paragraph.id,
            text: text,
            isCentered: paragraph.isCentered,
            imageSource: paragraph.imageSource,
            titleLevel: paragraph.titleLevel,
            notes: paragraph.notes.compactMap { mark in
                moved(mark.location, mark.length, among: places).map {
                    NoteMark(location: $0.location, length: $0.length, noteId: mark.noteId)
                }
            },
            scripts: paragraph.scripts.compactMap { mark in
                moved(mark.location, mark.length, among: places).map {
                    ScriptMark(location: $0.location, length: $0.length, place: mark.place)
                }
            }
        )
    }

    /// Where the characters the text arrived with ended up once the typesetter had been through it.
    ///
    /// Binding and hyphenation both put characters in — word joiners and soft hyphens — so a mark
    /// counted straight through would drift a little further with every one of them. Counting only
    /// the characters the text came with puts each one back where it was.
    private static func positions(in text: String) -> [Int] {
        let string = text as NSString
        var places: [Int] = []

        places.reserveCapacity(string.length)

        for index in 0 ..< string.length {
            let unit = string.character(at: index)
            let isFormat = Unicode.Scalar(unit).map { $0.properties.generalCategory == .format } ?? false

            if !isFormat { places.append(index) }
        }

        return places
    }

    /// One mark's stretch, moved to where those characters now stand.
    private static func moved(
        _ location: Int,
        _ length: Int,
        among places: [Int]
    ) -> (location: Int, length: Int)? {
        let last = location + length - 1

        guard location < places.count, last < places.count, last >= location else { return nil }

        let start = places[location]

        return (start, places[last] + 1 - start)
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
