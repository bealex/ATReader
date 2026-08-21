//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import Foundation
import NaturalLanguage

/// A chapter's text, parsed and ready to lay out.
struct ChapterContent: Sendable {
    var paragraphs: [ChapterHTML.Paragraph]
    /// The language the chapter is written in, which decides which hyphenation dictionary lays it out
    /// and how it is shaped.
    var language: String?

    var isEmpty: Bool { paragraphs.isEmpty }

    /// Parses a chapter body and works out its language away from the main actor.
    static func prepare(html: String) async -> ChapterContent {
        await Task.detached(priority: .userInitiated) {
            let paragraphs = ChapterHTML.paragraphs(from: html)
            let language = Self.language(of: paragraphs)
            return ChapterContent(paragraphs: paragraphs, language: language)
        }.value
    }

    private static func language(of paragraphs: [ChapterHTML.Paragraph]) -> String? {
        let sample = paragraphs.prefix(8).map(\.text).joined(separator: " ").prefix(1200)

        guard !sample.isEmpty else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(sample))
        return recognizer.dominantLanguage?.rawValue
    }
}
