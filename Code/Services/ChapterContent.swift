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
    /// The same paragraphs with every break point the language's dictionary allows already marked.
    /// Justified setting uses these; working them out costs about as much as laying the chapter out,
    /// so it happens once here rather than on every re-pagination.
    var hyphenated: [ChapterHTML.Paragraph]
    /// The language the chapter is written in, which decides which hyphenation dictionary lays it out
    /// and how it is shaped.
    var language: String?

    var isEmpty: Bool { paragraphs.isEmpty }

    /// Parses a chapter body, works out its language and binds the words its typography won't let a
    /// line break between, all away from the main actor.
    static func prepare(html: String) async -> ChapterContent {
        await Task.detached(priority: .userInitiated) {
            let paragraphs = ChapterHTML.paragraphs(from: html)
            let language = Self.language(of: paragraphs)
            let bound = paragraphs.map { paragraph in
                ChapterHTML.Paragraph(
                    id: paragraph.id,
                    text: Typography.bound(paragraph.text, language: language),
                    isCentered: paragraph.isCentered
                )
            }
            let hyphenated = bound.map { paragraph in
                ChapterHTML.Paragraph(
                    id: paragraph.id,
                    text: Typography.hyphenated(paragraph.text, language: language),
                    isCentered: paragraph.isCentered
                )
            }
            return ChapterContent(paragraphs: bound, hyphenated: hyphenated, language: language)
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
