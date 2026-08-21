//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import CoreText
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

/// Turns a chapter into fixed-size pages.
enum ChapterPagination {
    /// Builds the chapter as one attributed string: the heading, then one paragraph per block.
    ///
    /// Centred blocks (scene breaks, epigraphs) keep their own alignment whatever the reader chose —
    /// justifying a one-line epigraph looks like a bug.
    static func attributedText(
        for paragraphs: [ChapterHTML.Paragraph],
        heading: ChapterHeading = ChapterHeading(),
        language: String? = nil,
        style: ChapterTextStyle
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = style.font
        let bodyAlignment: NSTextAlignment = style.isJustified ? .justified : .natural

        append(heading, to: result, style: style)

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
            result.append(NSAttributedString(string: paragraph.text + suffix, attributes: attributes))
        }

        return result
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

    /// Splits the text into the ranges that fit successive frames of `size`.
    ///
    /// `CTFrameGetVisibleStringRange` reports what actually fitted, so this walks the string a page at a
    /// time rather than guessing from character counts.
    static func pageRanges(in text: NSAttributedString, size: CGSize) -> [NSRange] {
        guard text.length > 0, size.width > 1, size.height > 1 else { return [] }

        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
        var ranges: [NSRange] = []
        var location = 0

        while location < text.length {
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)

            // A page that fits nothing means the frame is too small for even one line; bail rather
            // than spin forever.
            guard visible.length > 0 else { break }

            ranges.append(NSRange(location: location, length: visible.length))
            location += visible.length
        }

        return ranges
    }

    /// Paginates away from the main actor.
    ///
    /// Typesetting a long chapter is the one part of opening one that takes long enough to stutter a
    /// page turn, and none of it touches anything the main actor owns.
    static func pageRanges(
        for paragraphs: [ChapterHTML.Paragraph],
        heading: ChapterHeading,
        language: String?,
        style: ChapterTextStyle,
        size: CGSize
    ) async -> [NSRange] {
        await Task.detached(priority: .userInitiated) {
            let text = attributedText(for: paragraphs, heading: heading, language: language, style: style)
            return pageRanges(in: text, size: size)
        }.value
    }
}
