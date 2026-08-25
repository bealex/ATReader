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
    var weight: ReaderSettings.Weight
    var fontSize: Double
    var lineSpacing: Double
    /// Tracking, in points, added between every pair of letters. Negative tightens.
    var letterSpacing: Double
    /// Justification is settled per language, and which one a chapter is in isn't known until it has
    /// been parsed, so the style carries both answers and the typesetter picks.
    var justifiesRussian: Bool
    var justifiesEnglish: Bool
    var textColor: UIColor

    var font: UIFont { face.font(size: fontSize, weight: weight.uiWeight) }

    func justifies(_ language: String?) -> Bool {
        Typography.isRussian(language) ? justifiesRussian : justifiesEnglish
    }
}

/// The heading a chapter opens with.
struct ChapterHeading: Equatable, Sendable {
    /// The chapter's place in the book, left out when the chapter's own title already says it.
    var number: String?
    var title: String?

    var isEmpty: Bool { number == nil && (title?.isEmpty ?? true) }

    /// The heading as one line of plain words, which is what the body is compared against.
    var spokenText: String { [ number, title ].compactMap { $0 }.joined(separator: " ") }

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
        let bodyAlignment: NSTextAlignment = style.justifies(language) ? .justified : .natural

        append(heading, to: result, style: style)
        let headingLength = result.length
        let paragraphs = withoutRepeatedHeading(paragraphs, heading: heading)

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
            //
            // Justified text asks for every break the dictionary can give: the factor is the fullness
            // below which TextKit bothers to look for one, and the system's own value leaves lines it
            // could have broken, which is where the stretched lines came from. Ragged-right keeps the
            // system's restraint, since nothing there needs filling.
            if bodyAlignment == .justified {
                paragraphStyle.hyphenationFactor = 1
            } else {
                paragraphStyle.usesDefaultHyphenation = true
            }

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

    /// How many opening paragraphs may be given up to a heading the body repeats.
    private static let repeatedHeadingLimit = 3

    /// Drops the chapter's own restatement of its heading.
    ///
    /// A chapter usually arrives with its number and title as the first paragraphs of the body, and the
    /// reader sets a heading of its own above that, so both are on the page. The body's version is the
    /// one to lose: it is the same words in the body's own face.
    ///
    /// The paragraphs are taken together rather than one at a time, since a heading the contents give as
    /// one line often reaches the body as two. Each is dropped only while everything read so far is
    /// still the opening of the heading, so a body that merely starts on the same word keeps it.
    private static func withoutRepeatedHeading(
        _ paragraphs: [ChapterHTML.Paragraph],
        heading: ChapterHeading
    ) -> [ChapterHTML.Paragraph] {
        let wanted = plainWords(heading.spokenText)

        guard !wanted.isEmpty else { return paragraphs }

        var matched = ""
        var dropped = 0

        for paragraph in paragraphs.prefix(repeatedHeadingLimit) {
            let words = plainWords(paragraph.text)

            guard !words.isEmpty else { break }

            let candidate = matched.isEmpty ? words : matched + " " + words

            guard wanted.hasPrefix(candidate) else { break }

            matched = candidate
            dropped += 1

            if matched == wanted { break }
        }

        return Array(paragraphs.dropFirst(dropped))
    }

    /// The words of a line, with everything that isn't one thrown away: case, punctuation, and the
    /// joiners and soft hyphens the typesetter puts in to control where a line may break.
    private static func plainWords(_ text: String) -> String {
        var letters: [Character] = []

        for scalar in text.lowercased().unicodeScalars {
            // Soft hyphens and word joiners are dropped rather than spaced over: they sit inside words,
            // so spacing them would split one word into two and no heading would ever match.
            guard scalar.properties.generalCategory != .format else { continue }

            letters.append(CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " ")
        }

        let words: [Substring] = String(letters).split(separator: " ")
        return words.map(String.init).joined(separator: " ")
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
                    .font: style.face.font(size: style.fontSize * 0.8, weight: style.weight.uiWeight),
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
                    .font: bold(style.face.font(size: style.fontSize * 1.25, weight: style.weight.uiWeight)),
                    .foregroundColor: style.textColor,
                    .paragraphStyle: paragraphStyle,
                ]
            ))
        }

        // A blank line of its own, so the body starts clear of the heading whatever the line spacing is.
        let spacer = NSMutableParagraphStyle()
        spacer.paragraphSpacing = 0
        let spacerFont = style.face.font(size: style.fontSize * 0.7, weight: style.weight.uiWeight)
        text.append(NSAttributedString(string: "\n", attributes: [ .font: spacerFont, .paragraphStyle: spacer ]))
    }

    private static func bold(_ font: UIFont) -> UIFont {
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) else { return font }

        return UIFont(descriptor: descriptor, size: font.pointSize)
    }
}
