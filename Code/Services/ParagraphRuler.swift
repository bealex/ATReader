//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import CoreText
import UIKit

/// One paragraph measured once, so the width of any piece of it costs a subtraction.
///
/// The soft hyphens and joiners the typesetter puts in are taken out before measuring and again before
/// drawing, so what the breaker costs and what the page shows cannot part company.
struct ParagraphRuler {
    /// Where a line may end, and what the reader sees when it does.
    struct Break {
        /// Where the line after it starts, counted from the paragraph's own first character.
        var position: Int
        /// The line ends in the middle of a word, which the page rules count as a hyphen.
        var hyphenates: Bool
        /// The hyphen has to be drawn: the text carries a soft hyphen here rather than a real one.
        var drawsHyphen: Bool
        /// A tie holds this shut, so breaking here leaves a short word at the end of a line.
        var tied: Bool
    }

    let range: NSRange
    let font: UIFont
    let alignment: NSTextAlignment
    let firstLineIndent: CGFloat
    let lineSpacing: CGFloat
    let paragraphSpacing: CGFloat
    let breaks: [Break]

    let spaceWidth: CGFloat
    let hyphenWidth: CGFloat

    /// The paragraph with everything invisible taken out, which is what was measured and what is drawn.
    private let visible: NSAttributedString
    /// Where each character of the visible text sits when the paragraph is set as one unbroken line.
    private let offsets: [CGFloat]
    /// Each position in the paragraph, counted in the visible text instead.
    private let places: [Int]
    /// How many spaces stand before each position, so a line's gaps are a subtraction too.
    private let spacesBefore: [Int]
    /// The paragraph as it was written, which is what the breaker reads to recognise a dash or a space.
    private let source: [unichar]

    /// The length of the paragraph, its trailing newline included.
    var length: Int { range.length }

    /// True where the paragraph has no text of its own and stands only for the space it takes.
    var isBlank: Bool { visible.length == 0 }

    init?(text: NSAttributedString, range: NSRange) {
        guard range.length > 0, NSMaxRange(range) <= text.length else { return nil }

        let string = text.string as NSString
        let style = text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont

        self.range = range
        self.font = font ?? .systemFont(ofSize: 17)
        self.alignment = style?.alignment ?? .natural
        self.firstLineIndent = style?.firstLineHeadIndent ?? 0
        self.lineSpacing = style?.lineSpacing ?? 0
        self.paragraphSpacing = style?.paragraphSpacing ?? 0

        let skeleton = Self.skeleton(of: string, range: range)
        let piece = Self.visibleText(of: text, range: range, runs: skeleton.visibleRuns)

        self.places = skeleton.places
        self.spacesBefore = skeleton.spacesBefore
        self.source = skeleton.source
        self.visible = piece

        let attributes: [NSAttributedString.Key: Any] = [ .font: self.font ]
        self.spaceWidth = (" " as NSString).size(withAttributes: attributes).width
        self.hyphenWidth = ("-" as NSString).size(withAttributes: attributes).width
        self.offsets = Self.offsets(of: piece)
        self.breaks = Self.breaks(in: string, range: range)
    }

    /// Where each character of the paragraph lands once the invisibles are taken out of it.
    private struct Skeleton {
        var places: [Int]
        var spacesBefore: [Int]
        var source: [unichar]
        var visibleRuns: [NSRange]
    }

    private static func skeleton(of string: NSString, range: NSRange) -> Skeleton {
        var places = [Int](repeating: 0, count: range.length + 1)
        var spacesBefore = [Int](repeating: 0, count: range.length + 1)
        var source = [unichar]()
        var runs: [NSRange] = []
        var runStart: Int?
        var seen = 0
        var spaces = 0

        source.reserveCapacity(range.length)

        for offset in 0 ..< range.length {
            places[offset] = seen
            spacesBefore[offset] = spaces

            let character = string.character(at: range.location + offset)
            source.append(character)

            if character == 0x20 { spaces += 1 }

            if isInvisible(character) {
                if let start = runStart {
                    runs.append(NSRange(location: start, length: offset - start))
                    runStart = nil
                }
            } else {
                if runStart == nil { runStart = offset }

                seen += 1
            }
        }

        if let start = runStart { runs.append(NSRange(location: start, length: range.length - start)) }

        places[range.length] = seen
        spacesBefore[range.length] = spaces
        return Skeleton(places: places, spacesBefore: spacesBefore, source: source, visibleRuns: runs)
    }

    private static func visibleText(
        of text: NSAttributedString,
        range: NSRange,
        runs: [NSRange]
    ) -> NSAttributedString {
        let piece = NSMutableAttributedString()

        for visible in runs {
            piece.append(text.attributedSubstring(from: NSRange(
                location: range.location + visible.location,
                length: visible.length
            )))
        }

        let whole = NSRange(location: 0, length: piece.length)

        // CoreText reads the paragraph style itself and would set the line to a measure of its own.
        piece.removeAttribute(.paragraphStyle, range: whole)

        // CoreText takes its colour from a key of its own; without this every page draws black.
        piece.enumerateAttribute(.foregroundColor, in: whole) { value, range, _ in
            guard let color = value as? UIColor else { return }

            piece.addAttribute(foregroundColor, value: color.cgColor, range: range)
        }

        return piece
    }

    /// Where every character sits when the paragraph is set as one unbroken line.
    private static func offsets(of piece: NSAttributedString) -> [CGFloat] {
        var result = [CGFloat](repeating: 0, count: piece.length + 1)

        guard piece.length > 0 else { return result }

        let line = CTLineCreateWithAttributedString(piece)

        for index in 0 ..< piece.length {
            result[index] = CTLineGetOffsetForStringIndex(line, index, nil)
        }

        result[piece.length] = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        return result
    }

    // MARK: - Measuring a piece of it

    /// Where a line drawn from `start` to `ending` actually stops, its trailing space given up.
    func content(from start: Int, to ending: Int) -> Int {
        var last = ending

        while last > start, Self.isBlank(character(at: last - 1)) { last -= 1 }

        return last
    }

    /// How wide a piece of the paragraph is when it is set the way the font sets it.
    func width(from start: Int, to ending: Int) -> CGFloat {
        offsets[places[ending]] - offsets[places[start]]
    }

    /// How many spaces a piece of the paragraph has to open, the one held after a dash aside.
    func gaps(from start: Int, to ending: Int) -> Int {
        spacesBefore[ending] - spacesBefore[start]
    }

    /// How many characters a piece actually draws, which is what its tracking is spread between.
    func characters(from start: Int, to ending: Int) -> Int {
        places[ending] - places[start]
    }

    /// A character of the paragraph as it was written, invisibles and all.
    func character(at offset: Int) -> unichar {
        offset >= 0 && offset < source.count ? source[offset] : 0
    }

    /// The line set for drawing: its own text, with the tracking and the gap widths worked into it.
    func setting(from start: Int, to ending: Int, fill: LineFill, holdsFirstGap: Bool, drawsHyphen: Bool) -> CTLine? {
        let first = places[start]
        let last = places[ending]

        guard last > first else { return nil }

        let piece = NSMutableAttributedString(
            attributedString: visible.attributedSubstring(from: NSRange(location: first, length: last - first))
        )

        if drawsHyphen {
            let tail = piece.attributes(at: piece.length - 1, effectiveRange: nil)
            piece.append(NSAttributedString(string: "-", attributes: tail))
        }

        if fill.glyphScale != 1 { Self.widen(piece, by: fill.glyphScale) }

        let text = piece.string as NSString
        var held = holdsFirstGap

        for index in 0 ..< piece.length - 1 {
            let base = (piece.attribute(.kern, at: index, effectiveRange: nil) as? NSNumber)?.doubleValue ?? 0
            var kern = CGFloat(base) + fill.perLetter

            if text.character(at: index) == 0x20 {
                if held {
                    kern = CGFloat(base)
                    held = false
                } else {
                    kern += fill.perGap
                }
            }

            piece.addAttribute(.kern, value: kern, range: NSRange(location: index, length: 1))
        }

        // Kern after the last character is advance belonging to no glyph, which would push the line's
        // ink past the measure it was set to.
        piece.removeAttribute(.kern, range: NSRange(location: piece.length - 1, length: 1))
        return CTLineCreateWithAttributedString(piece)
    }

    /// Draws the glyphs wider than the font draws them, which is the last lever a line has to fill.
    private static func widen(_ piece: NSMutableAttributedString, by scale: CGFloat) {
        piece.enumerateAttribute(.font, in: NSRange(location: 0, length: piece.length)) { value, range, _ in
            guard let font = value as? UIFont else { return }

            var matrix = CGAffineTransform(scaleX: scale, y: 1)
            let widened = CTFontCreateCopyWithAttributes(font, font.pointSize, &matrix, nil)
            piece.addAttribute(.font, value: widened, range: range)
        }
    }

    // MARK: - Where a line may end

    private static func breaks(in string: NSString, range: NSRange) -> [Break] {
        var result: [Break] = []

        for offset in 1 ..< max(1, range.length) {
            let previous = string.character(at: range.location + offset - 1)

            if previous == 0x20 {
                let next = range.location + offset
                let tied = next < string.length && string.character(at: next) == wordJoiner
                result.append(Break(position: offset, hyphenates: false, drawsHyphen: false, tied: tied))
            } else if previous == softHyphen {
                result.append(Break(position: offset, hyphenates: true, drawsHyphen: true, tied: false))
            } else if previous == 0x002D, breaksInsideAWord(string, at: range.location + offset) {
                result.append(Break(position: offset, hyphenates: true, drawsHyphen: false, tied: false))
            }
        }

        return result
    }

    /// True where a hyphen already written into a word may end a line, with letters enough either side.
    private static func breaksInsideAWord(_ string: NSString, at position: Int) -> Bool {
        guard position >= 3, position + 1 < string.length else { return false }

        let before = [ string.character(at: position - 3), string.character(at: position - 2) ]
        let after = [ string.character(at: position), string.character(at: position + 1) ]

        return (before + after).allSatisfy { character in
            guard let scalar = Unicode.Scalar(character) else { return false }

            return CharacterSet.letters.contains(scalar)
        }
    }

    private static let foregroundColor = NSAttributedString.Key(kCTForegroundColorAttributeName as String)

    static let softHyphen = unichar(0x00AD)
    /// Ties a short word to the one after it, so no line may end on it.
    static let wordJoiner = unichar(0x2060)

    static func isBlank(_ character: unichar) -> Bool { character == 0x20 || character == 0x0A }

    /// What the typesetter put in to steer the breaking and nobody is meant to see.
    private static func isInvisible(_ character: unichar) -> Bool {
        character == softHyphen || character == wordJoiner || character == 0x200B || character == 0x0A
    }
}
