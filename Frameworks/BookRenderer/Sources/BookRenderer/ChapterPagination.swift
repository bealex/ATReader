//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import UIKit

/// Everything about the page that changes how text lays out.
///
/// Pagination and drawing both build their attributed text from this, so the page breaks the reader
/// measures are exactly the ones it draws. Margins are deliberately absent — they shrink the frame the
/// text is laid into rather than the text itself.
public struct ChapterTextStyle: Equatable, Sendable {
    public var face: BookFace
    public var weight: BookWeight
    public var fontSize: Double
    public var lineSpacing: Double
    /// Tracking, in points, added between every pair of letters. Negative tightens.
    public var letterSpacing: Double
    /// Justification is settled per language, and which one a chapter is in isn't known until it has
    /// been parsed, so the style carries both answers and the typesetter picks.
    public var justifiesRussian: Bool
    public var justifiesEnglish: Bool
    public var textColor: UIColor
    /// The colour the page is set on, which pictures are drawn against as well as text.
    public var backgroundColor: UIColor = .systemBackground
    /// Every picture is held to the page's two colours, colour art included.
    public var monochromeImages: Bool = false
    /// False for text that is not a page of the book. A paragraph opens indented because the one
    /// before it ended somewhere unpredictable; an aside standing alone has nothing to be told apart
    /// from, so the indent only loses it a line's worth of room.
    public var indentsParagraphs: Bool = true

    public init(
        face: BookFace,
        weight: BookWeight,
        fontSize: Double,
        lineSpacing: Double,
        letterSpacing: Double,
        justifiesRussian: Bool,
        justifiesEnglish: Bool,
        textColor: UIColor,
        backgroundColor: UIColor = .systemBackground,
        monochromeImages: Bool = false,
        indentsParagraphs: Bool = true
    ) {
        self.face = face
        self.weight = weight
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.letterSpacing = letterSpacing
        self.justifiesRussian = justifiesRussian
        self.justifiesEnglish = justifiesEnglish
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.monochromeImages = monochromeImages
        self.indentsParagraphs = indentsParagraphs
    }

    public var font: UIFont { face.font(size: fontSize, weight: weight.uiWeight) }

    /// How deep one line of the page runs, which is what air around a title is counted in.
    ///
    /// One definition, since it is written down in one place and cut back in another: a title's air is
    /// laid out here and trimmed by `ChapterLayout` where the title opens a page, and the two counting
    /// lines differently left the trim taking more than it was asked for.
    public var pageLine: CGFloat { font.lineHeight + lineSpacing }

    public var palette: PagePalette {
        PagePalette(foreground: textColor, background: backgroundColor, isMonochrome: monochromeImages)
    }

    public func justifies(_ language: String?) -> Bool {
        Typography.isRussian(language) ? justifiesRussian : justifiesEnglish
    }
}

/// The heading a chapter opens with.
public struct ChapterHeading: Equatable, Sendable {
    /// The chapter's place in the book, left out when the chapter's own title already says it.
    public var number: String?
    public var title: String?

    public init(number: String? = nil, title: String? = nil) {
        self.number = number
        self.title = title
    }

    public var isEmpty: Bool { number == nil && (title?.isEmpty ?? true) }

    /// The heading as one line of plain words, which is what the body is compared against.
    public var spokenText: String { [ number, title ].compactMap { $0 }.joined(separator: " ") }

    /// Numbers a chapter unless its title already does — "Chapter 4" above "Chapter 4. The Road" reads
    /// like a bug rather than a heading.
    public static func make(position: Int, title: String?) -> ChapterHeading {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = String(localized: "Chapter \(position)", bundle: .module)

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
public enum ChapterPagination {
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
        paragraphs: [Paragraph],
        heading: ChapterHeading = ChapterHeading(),
        language: String? = nil,
        style: ChapterTextStyle,
        images: [String: PageImage] = [:]
    ) -> TypesetText {
        let result = NSMutableAttributedString()
        let font = style.font
        let bodyAlignment: NSTextAlignment = style.justifies(language) ? .justified : .natural

        append(heading, to: result, style: style)
        let headingLength = result.length
        let paragraphs = withoutRepeatedHeading(paragraphs, heading: heading)
        // Read once for the whole chapter: a paragraph's air depends on the titles it stands among.
        let levels = paragraphs.map(\.titleLevel)
        let opening = TitleBlock.opening(levels)
        let closing = TitleBlock.closing(levels)

        for (index, paragraph) in paragraphs.enumerated() {
            let suffix = index == paragraphs.count - 1 ? "" : "\n"

            if let source = paragraph.imageSource {
                // A picture the device has nothing behind stands for nothing, so its block goes rather
                // than leaving a hole where it would have been.
                if let picture = images[source] {
                    result.append(Self.setting(picture, suffix: suffix, style: style))
                }

                continue
            }

            // A title stands in the middle of the measure whether or not the book said so: left where
            // the paragraphs are, it reads as a line of text that lost its words.
            let isCentered = paragraph.isCentered || levels[index] != nil
            let air = Self.spacing(at: index, opening: opening, closing: closing, style: style, font: font)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = isCentered ? .center : bodyAlignment
            paragraphStyle.lineSpacing = style.lineSpacing
            paragraphStyle.paragraphSpacing = air.after
            paragraphStyle.paragraphSpacingBefore = air.before
            paragraphStyle.firstLineHeadIndent = isCentered || !style.indentsParagraphs ? 0 : font.pointSize
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

            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: style.textColor,
                .paragraphStyle: paragraphStyle,
            ]
            attributes.merge(languageAttributes(language)) { current, _ in current }
            if style.letterSpacing != 0 { attributes[.kern] = style.letterSpacing }

            let start = result.length
            result.append(NSAttributedString(string: paragraph.text + suffix, attributes: attributes))
            mark(paragraph.notes, in: result, from: start, style: style)
            raise(paragraph.scripts, in: result, from: start, style: style)
        }

        return TypesetText(attributed: result, headingLength: headingLength)
    }

    /// How deep the gap under a paragraph runs, and how much air stands above it.
    ///
    /// A title block stands in air worked out from the biggest title in it, and is parted from the
    /// text under it by the same measure. Everything else takes the gap paragraphs take between them.
    private static func spacing(
        at index: Int,
        opening: [Int?],
        closing: [Bool],
        style: ChapterTextStyle,
        font: UIFont
    ) -> (before: CGFloat, after: CGFloat) {
        let gap = style.lineSpacing * 0.8
        let line = style.pageLine
        let air = opening[index].map { TitleBlock.air(forLevel: $0) } ?? 0

        return (air * line, closing[index] ? gap + TitleBlock.gap(after: air) * line : gap)
    }

    /// Sets the stretches a formula drops below the line or lifts above it.
    private static func raise(
        _ scripts: [ScriptMark],
        in text: NSMutableAttributedString,
        from start: Int,
        style: ChapterTextStyle
    ) {
        guard !scripts.isEmpty else { return }

        let font = style.face.font(size: style.fontSize * NoteMarker.scale, weight: style.weight.uiWeight)

        for script in scripts {
            let range = NSRange(location: start + script.location, length: script.length)

            guard NSMaxRange(range) <= text.length else { continue }

            text.addAttributes(
                [
                    .font: font,
                    .baselineOffset: ScriptMarker.baselineOffset(script.place, forFontSize: style.fontSize),
                ],
                range: range
            )
        }
    }

    /// Sets a paragraph's note markers as references rather than as digits that wandered into the words.
    ///
    /// The characters are the ones the text arrived with. A reading position is an offset into that
    /// text, so a marker renumbered here would move the reader's place in every book on the device.
    private static func mark(
        _ notes: [NoteMark],
        in text: NSMutableAttributedString,
        from start: Int,
        style: ChapterTextStyle
    ) {
        guard !notes.isEmpty else { return }

        let font = style.face.font(size: style.fontSize * NoteMarker.scale, weight: style.weight.uiWeight)

        for note in notes {
            let range = NSRange(location: start + note.location, length: note.length)

            guard NSMaxRange(range) <= text.length else { continue }

            text.addAttributes(
                [
                    .font: font,
                    .baselineOffset: NoteMarker.baselineOffset(forFontSize: style.fontSize),
                    .bookNote: note.noteId,
                ],
                range: range
            )
        }
    }

    /// A picture as one block of the chapter.
    ///
    /// It stands for a single character, so a reading position counts it the way it counts a paragraph
    /// and stays put when the page size or the face changes. The column reads the picture off the
    /// character's own attribute and sets a line as deep as the picture is drawn.
    private static func setting(_ picture: PageImage, suffix: String, style: ChapterTextStyle) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = style.lineSpacing
        paragraphStyle.paragraphSpacing = style.lineSpacing * 0.8

        return NSAttributedString(
            string: String(Self.pictureMark) + suffix,
            attributes: [
                .font: style.font,
                .paragraphStyle: paragraphStyle,
                .pageImage: picture,
            ]
        )
    }

    /// What a picture stands as in the text. VoiceOver is told it is there; nothing draws it.
    public static let pictureMark: Character = "\u{FFFC}"

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
        _ paragraphs: [Paragraph],
        heading: ChapterHeading
    ) -> [Paragraph] {
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

    /// A chapter's own heading, which is the first-level title of the block it opens.
    ///
    /// The air above it is dropped where the chapter starts a page, since air at the head of a page
    /// says nothing. `ChapterLayout` does that, because only it knows where the chapter begins.
    private static func append(_ heading: ChapterHeading, to text: NSMutableAttributedString, style: ChapterTextStyle) {
        guard !heading.isEmpty else { return }

        let line = style.pageLine
        let above = TitleBlock.air(forLevel: 1) * line
        let below = TitleBlock.gap(after: TitleBlock.air(forLevel: 1)) * line
        let hasTitle = heading.title?.isEmpty == false

        if let number = heading.number {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            paragraphStyle.paragraphSpacingBefore = above
            paragraphStyle.paragraphSpacing = hasTitle ? style.fontSize * 0.4 : below

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
            paragraphStyle.paragraphSpacingBefore = heading.number == nil ? above : 0
            paragraphStyle.paragraphSpacing = below

            text.append(NSAttributedString(
                string: title + "\n",
                attributes: [
                    .font: bold(style.face.font(size: style.fontSize * 1.25, weight: style.weight.uiWeight)),
                    .foregroundColor: style.textColor,
                    .paragraphStyle: paragraphStyle,
                ]
            ))
        }
    }

    private static func bold(_ font: UIFont) -> UIFont {
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) else { return font }

        return UIFont(descriptor: descriptor, size: font.pointSize)
    }
}
