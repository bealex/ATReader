//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import UIKit

/// Everything about the page that changes how text lays out.
///
/// Pagination and drawing both build their attributed text from this, so the page breaks the reader
/// measures are exactly the ones it draws. Margins are deliberately absent — they shrink the frame the
/// text is laid into rather than the text itself.
struct ChapterTextStyle: Equatable, Sendable {
    var face: ReaderSettings.Face
    var fontSize: Double
    var lineSpacing: Double
    /// Tracking, in points, added between every pair of letters. Negative tightens.
    var letterSpacing: Double
    var isJustified: Bool
    var textColor: UIColor

    var font: UIFont { face.font(size: fontSize) }
}

/// The heading a chapter opens with.
struct ChapterHeading: Equatable, Sendable {
    /// The chapter's place in the book, left out when the chapter's own title already says it.
    var number: String?
    var title: String?

    var isEmpty: Bool { number == nil && (title?.isEmpty ?? true) }

    /// Numbers a chapter unless its title already does — "Chapter 4" above "Chapter 4. The Road" reads
    /// like a bug rather than a heading.
    static func make(position: Int, title: String?) -> ChapterHeading {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = String(localized: "Chapter \(position)")

        guard let trimmed, !trimmed.isEmpty else { return ChapterHeading(number: number, title: nil) }
        guard !isSelfNumbering(trimmed) else { return ChapterHeading(number: nil, title: trimmed) }

        return ChapterHeading(number: number, title: trimmed)
    }

    private static let numberingPrefixes = [
        "глава", "часть", "том", "пролог", "эпилог", "интерлюдия",
        "chapter", "part", "book", "prologue", "epilogue", "interlude",
    ]

    private static func isSelfNumbering(_ title: String) -> Bool {
        let lowered = title.lowercased()

        if numberingPrefixes.contains(where: { lowered.hasPrefix($0) }) { return true }

        return title.range(of: "^[0-9IVXivx]+[.)]?\\s", options: .regularExpression) != nil
    }
}

/// Sets a chapter as text: the heading, then the body, styled as the reader asked.
enum ChapterPagination {
    /// A chapter set as one attributed string, with the length of its heading, which the page breaker
    /// needs so a heading is never left at the foot of a page without its text.
    struct TypesetText {
        var attributed: NSAttributedString
        var headingLength: Int
    }

    /// Builds the chapter as one attributed string: the heading, then one paragraph per block.
    ///
    /// Centred blocks (scene breaks, epigraphs) keep their own alignment whatever the reader chose —
    /// justifying a one-line epigraph looks like a bug.
    static func typeset(
        paragraphs: [ChapterHTML.Paragraph],
        heading: ChapterHeading = ChapterHeading(),
        language: String? = nil,
        style: ChapterTextStyle
    ) -> TypesetText {
        let result = NSMutableAttributedString()
        let font = style.font
        let bodyAlignment: NSTextAlignment = style.isJustified ? .justified : .natural

        append(heading, to: result, style: style)
        let headingLength = result.length

        for (index, paragraph) in paragraphs.enumerated() {
            let isCentered = paragraph.isCentered
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = isCentered ? .center : bodyAlignment
            paragraphStyle.lineSpacing = style.lineSpacing
            paragraphStyle.paragraphSpacing = style.lineSpacing * 0.8
            paragraphStyle.firstLineHeadIndent = isCentered ? 0 : font.pointSize
            paragraphStyle.lineBreakMode = .byWordWrapping
            // Hyphenation, from the system's dictionary for the language the run carries. Without it a
            // justified narrow column pulls the words apart instead of breaking them.
            paragraphStyle.usesDefaultHyphenation = true

            let suffix = index == paragraphs.count - 1 ? "" : "\n"
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: style.textColor,
                .paragraphStyle: paragraphStyle,
            ]
            attributes.merge(languageAttributes(language)) { current, _ in current }
            if style.letterSpacing != 0 { attributes[.kern] = style.letterSpacing }
            result.append(NSAttributedString(string: paragraph.text + suffix, attributes: attributes))
        }

        return TypesetText(attributed: result, headingLength: headingLength)
    }

    /// Hyphenation needs to know the language. Without it, justified Russian stretches the space between
    /// letters instead of breaking a word, which is what the loose-looking lines were.
    private static func languageAttributes(_ language: String?) -> [NSAttributedString.Key: Any] {
        guard let language else { return [:] }

        // `languageIdentifier` is CoreText's own `kCTLanguageAttributeName` under a Foundation name.
        return [ .languageIdentifier: language ]
    }

    private static func append(_ heading: ChapterHeading, to text: NSMutableAttributedString, style: ChapterTextStyle) {
        guard !heading.isEmpty else { return }

        if let number = heading.number {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            paragraphStyle.paragraphSpacing = style.fontSize * 0.4

            text.append(NSAttributedString(
                string: number.uppercased() + "\n",
                attributes: [
                    .font: style.face.font(size: style.fontSize * 0.8),
                    .foregroundColor: style.textColor.withAlphaComponent(0.55),
                    .kern: style.fontSize * 0.08,
                    .paragraphStyle: paragraphStyle,
                ]
            ))
        }

        if let title = heading.title, !title.isEmpty {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            paragraphStyle.lineSpacing = style.lineSpacing * 0.5

            text.append(NSAttributedString(
                string: title + "\n",
                attributes: [
                    .font: bold(style.face.font(size: style.fontSize * 1.25)),
                    .foregroundColor: style.textColor,
                    .paragraphStyle: paragraphStyle,
                ]
            ))
        }

        // A blank line of its own, so the body starts clear of the heading whatever the line spacing is.
        let spacer = NSMutableParagraphStyle()
        spacer.paragraphSpacing = 0
        text.append(NSAttributedString(
            string: "\n",
            attributes: [ .font: style.face.font(size: style.fontSize * 0.7), .paragraphStyle: spacer ]
        ))
    }

    private static func bold(_ font: UIFont) -> UIFont {
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) else { return font }

        return UIFont(descriptor: descriptor, size: font.pointSize)
    }
}
