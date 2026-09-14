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
    /// Whether words may be broken at the end of a line. A justified column reads far better with it,
    /// since the alternative to a hyphen is a line pulled apart to reach the measure.
    public var hyphenates: Bool = true
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
        hyphenates: Bool = true,
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
        self.hyphenates = hyphenates
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

    /// Whether a paragraph is told from the one before it by an indent rather than by air above it.
    ///
    /// The two traditions do it one way or the other and never both. Russian indents the first line and
    /// leaves no gap; English parts its paragraphs with space and indents nothing.
    public func indents(_ language: String?) -> Bool {
        indentsParagraphs && Typography.isRussian(language)
    }

    /// The air under a paragraph, which is what parts them where nothing is indented.
    public func paragraphGap(_ language: String?) -> CGFloat {
        indents(language) ? 0 : fontSize * ChapterPagination.partedParagraphGap
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
    ///
    /// A title that carries its own number is parted into the two the heading is set in, and the book's
    /// own words are used rather than the count, since a book with a prologue in it disagrees with the
    /// count and is right.
    public static func make(position: Int, title: String?) -> ChapterHeading {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = String(localized: "Chapter \(position)", bundle: .module)

        guard let trimmed, !trimmed.isEmpty else { return ChapterHeading(number: number, title: nil) }

        if let parted = HeadingNumbering.part(trimmed) {
            return ChapterHeading(number: parted.number, title: parted.name)
        }

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

extension NSAttributedString.Key {
    /// Marks a block the book set as verse, so the composer runs its long lines over rather than
    /// wrapping them like prose.
    static let verseLine = NSAttributedString.Key("ATVerseLine")

    /// Marks a block the book set as a scene break, so no page opens on one.
    static let sceneBreak = NSAttributedString.Key("ATSceneBreak")
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
        let read = reading(paragraphs, under: heading)

        append(read.heading, to: result, style: style)
        let headingLength = result.length
        let paragraphs = read.paragraphs
        let setting = Setting(paragraphs, language: language, style: style)
        let levels = setting.levels

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

            let paragraphStyle = Self.styling(paragraph, at: index, in: setting)

            // A book that names its own chapters is left to name them, so those lines have to read as
            // headings rather than as centred text that lost its face.
            var attributes: [NSAttributedString.Key: Any] = [
                .font: levels[index].map { Self.titleFont($0, style: style) } ?? font,
                .foregroundColor: style.textColor,
                .paragraphStyle: paragraphStyle,
            ]
            attributes.merge(languageAttributes(language)) { current, _ in current }
            if style.letterSpacing != 0 { attributes[.kern] = style.letterSpacing }

            if paragraph.isVerse { attributes[.verseLine] = true }
            if paragraph.isSceneBreak { attributes[.sceneBreak] = true }

            let start = result.length
            result.append(NSAttributedString(string: paragraph.text + suffix, attributes: attributes))
            // Before the markers, which set a face of their own on the stretch they cover.
            emphasise(paragraph.styles, in: result, from: start)
            connect(paragraph.links, in: result, from: start)
            mark(paragraph.notes, in: result, from: start, style: style)
            raise(paragraph.scripts, in: result, from: start, style: style)
        }

        return TypesetText(attributed: result, headingLength: headingLength)
    }

    /// What every block of one chapter is set against: the reader's own answers for the language it is
    /// written in, and where the titles and the quotations in it stand.
    private struct Setting {
        let style: ChapterTextStyle
        let body: NSTextAlignment
        let indentsBody: Bool
        let gap: CGFloat
        /// Read once for the whole chapter: a block's air depends on the titles it stands among.
        let levels: [Int?]
        let opening: [Int?]
        let closing: [Bool]
        /// Which blocks name whose words stood above them.
        let sources: [Bool]

        init(_ paragraphs: [Paragraph], language: String?, style: ChapterTextStyle) {
            self.style = style
            body = style.justifies(language) ? .justified : .natural
            indentsBody = style.indents(language)
            gap = style.paragraphGap(language)
            levels = paragraphs.map(\.titleLevel)
            opening = TitleBlock.opening(levels)
            closing = TitleBlock.closing(levels)
            sources = paragraphs.map(\.isSource)
        }
    }

    /// How one block is set: which edge it stands against, how far in, and the air around it.
    private static func styling(
        _ paragraph: Paragraph,
        at index: Int,
        in setting: Setting
    ) -> NSMutableParagraphStyle {
        let font = setting.style.font
        // A title stands in the middle of the measure whether or not the book said so: left where the
        // paragraphs are, it reads as a line of text that lost its words.
        let isCentered = paragraph.isCentered || setting.levels[index] != nil
        let air = spacing(at: index, in: setting)
        let style = NSMutableParagraphStyle()

        style.alignment = alignment(of: paragraph, centred: isCentered, body: setting.body)
        style.lineSpacing = setting.style.lineSpacing
        style.paragraphSpacing = air.after
        style.paragraphSpacingBefore = air.before
        style.firstLineHeadIndent = isCentered || !setting.indentsBody ? 0 : font.pointSize
        style.lineBreakMode = .byWordWrapping

        place(paragraph, in: style, font: font)

        // Hyphenation, from the system's dictionary for the language the run carries. Without it a
        // justified narrow column pulls the words apart instead of breaking them.
        //
        // Justified text asks for every break the dictionary can give: the factor is the fullness below
        // which TextKit bothers to look for one, and the system's own value leaves lines it could have
        // broken, which is where the stretched lines came from. Ragged-right keeps the system's
        // restraint, since nothing there needs filling.
        if paragraph.isVerse {
            // A poem's line is its own measure, and breaking a word across the end of one reads as a
            // fault rather than as setting.
            style.hyphenationFactor = 0
            style.usesDefaultHyphenation = false
        } else if setting.body == .justified {
            style.hyphenationFactor = 1
        } else {
            style.usesDefaultHyphenation = true
        }

        return style
    }

    /// Which edge a block is set against.
    ///
    /// A title stands in the middle of the measure whatever the book said, and a signature or a date
    /// against the right where the book put it there. So does the name under a quotation, which the
    /// book states by what it is rather than by setting it. Everything else takes the reader's own
    /// answer for the language it is written in.
    private static func alignment(
        of paragraph: Paragraph,
        centred: Bool,
        body: NSTextAlignment
    ) -> NSTextAlignment {
        if centred { return .center }
        if paragraph.isRightAligned { return .right }

        // Whose words a quotation was stands at the far edge of the quotation, which is where a book
        // sets an attribution. A quotation the book centred keeps its own axis, attribution and all.
        if paragraph.isSource { return .right }

        // A line of verse ends where the poet ended it, so filling it to the measure would be filling
        // a line nobody asked to be full.
        return paragraph.isVerse ? .natural : body
    }

    /// How a block stands among the text around it: how far in, and which way round.
    ///
    /// An item of a list stands in on every line of it, since the mark it opens with is part of its own
    /// text and there is nothing to hang outside the indent. Which way it runs came from the book
    /// rather than from the language, so a chapter of quoted English in an Arabic book is still set
    /// that way.
    private static func place(_ paragraph: Paragraph, in style: NSMutableParagraphStyle, font: UIFont) {
        if let depth = paragraph.listLevel {
            let indent = font.pointSize * listIndent * CGFloat(depth)

            style.headIndent = indent
            style.firstLineHeadIndent = indent
        }

        if paragraph.isRightToLeft { style.baseWritingDirection = .rightToLeft }

        // A passage the book held off both edges keeps that on the page: a quotation set at the
        // measure of the text around it reads as the text rather than as something quoted.
        guard paragraph.isInset else { return }

        let held = font.pointSize * insetMeasure * 2
        // The same air as before, laid four parts at the near edge to one at the far: a passage set
        // evenly between the two reads as text that was narrowed, where one pushed over reads as
        // quoted. Moving it rather than narrowing it leaves the measure alone, which a poem quoted as
        // an epigraph needs, since every line it loses is a line that has to run over.
        let near = held * insetBias / (insetBias + 1)

        style.headIndent = near
        style.firstLineHeadIndent = near
        // Counted from the right edge, which is what a negative tail indent means.
        style.tailIndent = -(held - near)
    }

    /// Sets the stretches a book marked apart in the face that says so.
    ///
    /// The face is read off whatever already stands there rather than from the style, so a phrase set
    /// both bold and slanted comes out as both rather than as whichever mark was applied last.
    private static func emphasise(_ styles: [StyleMark], in text: NSMutableAttributedString, from start: Int) {
        guard !styles.isEmpty else { return }

        for style in styles {
            let range = NSRange(location: start + style.location, length: style.length)

            guard range.length > 0, NSMaxRange(range) <= text.length else { continue }

            var found: [(NSRange, UIFont)] = []

            text.enumerateAttribute(.font, in: range) { value, range, _ in
                guard let font = value as? UIFont else { return }

                found.append((range, font))
            }

            for (range, font) in found {
                text.addAttribute(.font, value: adding(style.emphasis, to: font), range: range)
            }
        }
    }

    private static func adding(_ emphasis: StyleMark.Emphasis, to font: UIFont) -> UIFont {
        var traits = font.fontDescriptor.symbolicTraits

        switch emphasis {
            case .italic: traits.insert(.traitItalic)
            case .bold: traits.insert(.traitBold)
        }

        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return font }

        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    /// How far one level of a list stands in, against the size of the type.
    private static let listIndent: CGFloat = 1.4
    /// How far a quoted passage is held off each edge, against the size of the type.
    private static let insetMeasure: CGFloat = 1.6
    /// How much further a quotation stands from the near edge than from the far one.
    private static let insetBias: CGFloat = 4

    /// How deep the gap under a paragraph runs, and how much air stands above it.
    ///
    /// A title block stands in air worked out from the biggest title in it, and is parted from the
    /// text under it by the same measure. Everything else takes the gap paragraphs take between them.
    private static func spacing(at index: Int, in setting: Setting) -> (before: CGFloat, after: CGFloat) {
        let line = setting.style.pageLine
        let air = setting.opening[index].map { TitleBlock.air(forLevel: $0) } ?? 0
        // A quotation's source stands clear of the words it names, and whatever comes after one is no
        // longer part of that quotation, so it stands clear too. Without this two epigraphs over a
        // chapter read as one run of text.
        let apart = setting.sources[index] || (index > 0 && setting.sources[index - 1])
        let quoted = apart && air == 0 ? line : 0
        let after = setting.closing[index] ? setting.gap + TitleBlock.gap(after: air) * line : setting.gap

        return (air * line + quoted, after)
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
    /// Marks the stretches that point somewhere else in the book.
    ///
    /// Underlined rather than coloured: the page is set in one ink, and a second one would read as the
    /// book's own rather than as the reader's.
    private static func connect(_ links: [LinkMark], in text: NSMutableAttributedString, from start: Int) {
        guard !links.isEmpty else { return }

        for link in links {
            let range = NSRange(location: start + link.location, length: link.length)

            guard range.length > 0, NSMaxRange(range) <= text.length else { continue }

            text.addAttributes(
                [
                    .bookLink: link.target,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ],
                range: range
            )
        }
    }

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
    /// Which heading the page shows, and what is left of the body under it.
    ///
    /// A chapter usually arrives with its number and title as the first paragraphs of the body, and the
    /// reader sets a heading of its own above that, so both are on the page. Which one goes depends on
    /// what the body wrote them as.
    ///
    /// Written as ordinary text, the body's copy is the one to lose: it is the same words in the body's
    /// own face. Written as headings, the book is naming its own chapters, and then the reader's
    /// heading is the one to lose: a book that sets out its divisions is left to set them out.
    private static func reading(
        _ paragraphs: [Paragraph],
        under heading: ChapterHeading
    ) -> (heading: ChapterHeading, paragraphs: [Paragraph]) {
        let spoken = matched(paragraphs, against: plainWords(heading.spokenText))

        if spoken > 0 { return (heading, Array(paragraphs.dropFirst(spoken))) }

        let named = matched(paragraphs, against: plainWords(heading.title ?? ""))
        // Only where the book wrote them as headings. A paragraph that merely opens on the same words
        // is the text itself, and the chapter still wants a heading over it.
        let isNamed = named > 0 && paragraphs.prefix(named).allSatisfy { $0.titleLevel != nil }

        return isNamed ? (ChapterHeading(), paragraphs) : (heading, paragraphs)
    }

    /// How many of the opening blocks spell out the words wanted, or none where they do not.
    ///
    /// The blocks are taken together rather than one at a time, since a heading the contents give as one
    /// line often reaches the body as two. Each counts only while everything read so far is still the
    /// opening of what is wanted, so a body that merely starts on the same word matches nothing.
    private static func matched(_ paragraphs: [Paragraph], against wanted: String) -> Int {
        guard !wanted.isEmpty else { return 0 }

        var matched = ""
        var count = 0

        for paragraph in paragraphs.prefix(repeatedHeadingLimit) {
            let words = plainWords(paragraph.text)

            guard !words.isEmpty else { break }

            let candidate = matched.isEmpty ? words : matched + " " + words

            guard wanted.hasPrefix(candidate) else { break }

            matched = candidate
            count += 1

            if matched == wanted { return count }
        }

        // Half a heading is not the heading: the words have to be spelled out in full.
        return matched == wanted ? count : 0
    }

    /// The face a title standing in the body is set in.
    ///
    /// A book that names its own chapters is left to name them, so those lines are set as headings
    /// rather than as centred text. The air a title stands in is measured on top of this.
    public static func titleFont(_ level: Int, style: ChapterTextStyle) -> UIFont {
        let scale =
            switch level {
                case 1: bookTitleScale
                case 2: chapterTitleScale
                default: 1.0
            }

        return bold(style.face.font(size: style.fontSize * scale, weight: style.weight.uiWeight))
    }

    /// How far apart paragraphs stand where nothing indents them.
    static let partedParagraphGap: CGFloat = 0.45
    private static let bookTitleScale: CGFloat = 1.3
    private static let chapterTitleScale: CGFloat = 1.15

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
