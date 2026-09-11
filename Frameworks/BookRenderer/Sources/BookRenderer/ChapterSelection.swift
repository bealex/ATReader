//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import CoreText
import UIKit

/// Picking text off a page that is drawn rather than laid out by a text view.
///
/// A drawn page has no selection of its own, so every part of one is worked out here: which character
/// a finger is over, where the word around it starts and stops, and which boxes to paint under the
/// stretch between two fingers' worth of travel.
public extension ChapterLayout {
    /// A stretch of the chapter the reader has picked out.
    struct Selection: Equatable, Sendable {
        public let range: NSRange
        /// What it says, as it was written: no soft hyphens, no joiners.
        public let text: String
        /// How many words it covers, which is what decides whether copying it is worth offering.
        public let words: Int

        public var isEmpty: Bool { text.isEmpty }
        public var isPhrase: Bool { words > 1 }
    }

    /// The word under a point on a page.
    func word(at point: CGPoint, onPage index: Int) -> NSRange? {
        words(from: point, to: point, onPage: index)
    }

    /// Everything between two points, opened out to whole words at either end.
    func words(from start: CGPoint, to finish: CGPoint, onPage index: Int) -> NSRange? {
        guard
            let first = characterIndex(at: start, onPage: index),
            let last = characterIndex(at: finish, onPage: index)
        else { return nil }

        let lower = min(first, last)
        let upper = max(first, last)

        guard let opening = word(around: lower), let closing = word(around: upper) else { return nil }

        let opens = min(opening.location, closing.location)
        let past = max(NSMaxRange(opening), NSMaxRange(closing))
        return NSRange(location: opens, length: past - opens)
    }

    /// Where a stretch sits on a page: one box per line it runs through, in the page's own coordinates.
    func rects(of range: NSRange, onPage index: Int) -> [CGRect] {
        var result: [CGRect] = []

        for placed in placedLines(onPage: index) {
            let line = lines[placed.index]
            let shared = NSIntersectionRange(line.characters, range)

            guard shared.length > 0, let drawn = drawnLine(placed.index) else { continue }

            let origin = context.textRect.minX + line.origin
            let opening = CTLineGetOffsetForStringIndex(drawn, visible(ofSource: shared.location, in: line), nil)
            let closing = CTLineGetOffsetForStringIndex(drawn, visible(ofSource: NSMaxRange(shared), in: line), nil)

            result.append(CGRect(
                x: origin + min(opening, closing),
                y: placed.edge,
                width: abs(closing - opening),
                height: placed.height
            ))
        }

        return result
    }

    /// What a stretch says, and how much of it there is.
    func selection(of range: NSRange) -> Selection {
        let string = text.string as NSString

        guard
            range.location >= 0,
            NSMaxRange(range) <= string.length,
            range.length > 0
        else {
            return Selection(range: range, text: "", words: 0)
        }

        let written = string.substring(with: range)
            .replacingOccurrences(of: String(Typography.softHyphen), with: "")
            .replacingOccurrences(of: "\u{2060}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Selection(range: range, text: written, words: written.split(whereSeparator: \.isWhitespace).count)
    }

    // MARK: - Finding a character

    /// A line as it stands on a page: which line it is, and where its top edge and its depth are.
    struct PlacedLine {
        public let index: Int
        public let edge: CGFloat
        public let height: CGFloat
    }

    /// Every line of a page with the place it was drawn at, walked exactly as the page is drawn.
    func placedLines(onPage index: Int) -> [PlacedLine] {
        guard pages.indices.contains(index) else { return [] }

        let page = pages[index]
        var cursor = context.textRect.minY + (index == 0 ? startOffset : 0)
        var result: [PlacedLine] = []

        for line in page.lines {
            let allotted = lines[line].height + (lines[line].image != nil ? page.imagePadding * 2 : 0)

            result.append(PlacedLine(index: line, edge: cursor, height: allotted))
            cursor += allotted + page.leading
        }

        return result
    }

    /// Which character of the chapter a point on a page is over.
    ///
    /// A point past the end of a line takes that line's last character, and a point above or below the
    /// text takes the nearest line, so a finger dragging off the edge keeps choosing rather than stops.
    func characterIndex(at point: CGPoint, onPage index: Int) -> Int? {
        let placed = placedLines(onPage: index)

        guard !placed.isEmpty else { return nil }

        let over =
            placed.first { point.y >= $0.edge && point.y < $0.edge + $0.height }
            ?? placed.min { abs(point.y - $0.edge) < abs(point.y - $1.edge) }

        guard let over, let drawn = drawnLine(over.index) else { return nil }

        let line = lines[over.index]
        let along = point.x - context.textRect.minX - line.origin
        let found = CTLineGetStringIndexForPosition(drawn, CGPoint(x: along, y: 0))

        guard found != kCFNotFound else { return nil }

        return source(ofVisible: found, in: line)
    }

    // MARK: - Counting past what the typesetter put in

    /// Where a word standing at a character begins and ends.
    ///
    /// A point that landed between words takes the word before it, so a finger resting in a gap picks
    /// something rather than nothing.
    private func word(around index: Int) -> NSRange? {
        let string = text.string as NSString

        guard string.length > 0 else { return nil }

        var at = min(max(index, 0), string.length - 1)

        if !Self.isWordCharacter(string.character(at: at)) {
            guard at > 0, Self.isWordCharacter(string.character(at: at - 1)) else { return nil }

            at -= 1
        }

        var first = at
        var past = at + 1

        while first > 0, Self.isWordCharacter(string.character(at: first - 1)) { first -= 1 }
        while past < string.length, Self.isWordCharacter(string.character(at: past)) { past += 1 }

        return NSRange(location: first, length: past - first)
    }

    /// Letters and figures, and everything the typesetter buried inside a word: a soft hyphen, a joiner,
    /// the hyphen a compound is written with.
    private static func isWordCharacter(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return true }

        if scalar.properties.generalCategory == .format { return true }
        if CharacterSet.alphanumerics.contains(scalar) { return true }

        return scalar == "-" || scalar == "\u{2019}" || scalar == "'"
    }

    /// The chapter's own index for a character of a drawn line, which carries none of the invisibles.
    private func source(ofVisible visible: Int, in line: ColumnComposer.Line) -> Int {
        let string = text.string as NSString
        var seen = 0

        for offset in 0 ..< line.characters.length {
            let index = line.characters.location + offset

            guard !Self.isInvisible(string.character(at: index)) else { continue }

            if seen == visible { return index }

            seen += 1
        }

        return max(line.characters.location, NSMaxRange(line.characters) - 1)
    }

    /// The drawn line's own index for a character of the chapter.
    private func visible(ofSource source: Int, in line: ColumnComposer.Line) -> Int {
        let string = text.string as NSString
        var seen = 0

        for offset in 0 ..< line.characters.length {
            let index = line.characters.location + offset

            if index >= source { return seen }

            if !Self.isInvisible(string.character(at: index)) { seen += 1 }
        }

        return seen
    }

    /// What the typesetter put in and CoreText was never given: the marks that steer a line break.
    private static func isInvisible(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }

        return scalar.properties.generalCategory == .format
    }
}
