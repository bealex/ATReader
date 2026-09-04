//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import CoreText
import UIKit

/// How the slack on one line is shared out: between the gaps, between the letters, and last of all
/// inside the glyphs themselves.
///
/// The three move together rather than in turn. Each has its own ceiling and all three reach theirs at
/// the same moment, so a line with few gaps leans on its letters and a line with many leans on its gaps
/// without either being settled in advance.
struct LineFill {
    /// Added to every gap the line may open, on top of the tracking the gap already takes.
    var perGap: CGFloat = 0
    /// Tracking added between every pair of characters, the held gap aside.
    var perLetter: CGFloat = 0
    /// How far the glyphs are drawn wider than the font draws them.
    var glyphScale: CGFloat = 1
    /// What none of the three could reach, negative where the line is still too wide.
    var shortfall: CGFloat = 0
    /// How far the levers stand towards their comfortable ceilings, from nothing to all of it.
    var reach: CGFloat = 0

    /// What one line has to give: how many gaps and pairs of letters it can open, and against what.
    struct Room {
        var gaps: Int
        var letters: Int
        /// What the line already covers, which is what the glyphs are widened against.
        var inkWidth: CGFloat
        var spaceWidth: CGFloat
        var fontSize: CGFloat
        /// False on a line that stops where its words stop, which never reaches for the last lever.
        var widensGlyphs: Bool
    }

    /// Shares a line's slack out over the room it has, negative slack closing it up instead.
    static func solve(slack: CGFloat, in room: Room) -> LineFill {
        typealias Rules = ColumnComposer.Rules

        var fill = LineFill()

        guard slack != 0 else { return fill }

        let stretching = slack > 0
        let perGapLimit = room.spaceWidth * (stretching ? Rules.gapStretch : Rules.gapSqueeze)
        let perLetterLimit = room.fontSize * (stretching ? Rules.letterStretch : Rules.letterSqueeze)
        let capacity = CGFloat(room.gaps) * perGapLimit + CGFloat(room.letters) * perLetterLimit
        let wanted = abs(slack)
        let sign: CGFloat = stretching ? 1 : -1

        guard
            capacity > 0
        else {
            fill.shortfall = slack
            return fill
        }

        fill.reach = min(1, wanted / capacity)
        fill.perGap = sign * fill.reach * perGapLimit
        fill.perLetter = sign * fill.reach * perLetterLimit

        var left = wanted - fill.reach * capacity

        // Past the comfortable point the gaps go on alone. Tracking further apart than this stops
        // reading as colour and starts reading as a different face.
        if stretching, left > 0, room.gaps > 0 {
            let wider = room.spaceWidth * (Rules.gapCeiling - Rules.gapStretch) * CGFloat(room.gaps)
            let taken = min(wider, left)

            fill.perGap += taken / CGFloat(room.gaps)
            left -= taken
        }

        if stretching, room.widensGlyphs, left > 0, room.inkWidth > 0 {
            let widening = min(Rules.glyphStretch, left / room.inkWidth)
            fill.glyphScale = 1 + widening
            left -= widening * room.inkWidth
        }

        fill.shortfall = sign * left
        return fill
    }
}

/// Breaks a chapter into lines and settles how each of them is filled.
///
/// The breaking is the column's own rather than TextKit's, so where a line ends and how it is filled are
/// one decision instead of two: every arrangement of a paragraph's breaks is costed by how hard its
/// lines have to be pushed to reach the measure, and the cheapest arrangement wins.
@MainActor
final class ColumnComposer {
    enum Rules {
        /// How far a gap may open before it stops sharing the slack with the letters, against its own
        /// width. Up to here the two move together; past it the gaps go on alone.
        static let gapStretch: CGFloat = 1.6
        /// How far a gap may open at all, against its own width. Past this the words read as too far
        /// apart to be one line, and the line is left short instead.
        static let gapCeiling: CGFloat = 5.2
        /// How far a gap may close, against its own width.
        static let gapSqueeze: CGFloat = 0.3
        /// How far apart the letters may stand to help fill a line, as a share of the type size.
        static let letterStretch: CGFloat = 0.035
        /// How far the letters may close up to save a word from being broken, as a share of the type size.
        static let letterSqueeze: CGFloat = 0.02
        /// How far the glyphs themselves may be widened, against their own width. Last of the three and
        /// much the smallest: widening a glyph changes its weight, which shows sooner than space does.
        static let glyphStretch: CGFloat = 0.012
        /// What closing a line up costs against opening it as far, since words run together worse than
        /// they drift apart.
        static let squeezePenalty: Double = 3
        /// What a line none of the levers could fill costs, per space width it falls short.
        static let shortPenalty: Double = 12
        /// What a line that will not fit at all costs, per space width it overruns.
        static let overrunPenalty: Double = 400
        /// What a line whose gaps had to go on alone costs, per space width each of them stands open
        /// past the comfortable point. Dear enough that a second broken word is the cheaper answer.
        static let openGapPenalty: Double = 6
        /// How uneven a ragged edge may be before it is worth breaking a line differently.
        static let raggedPenalty: Double = 4
        /// What breaking a word costs.
        static let hyphenPenalty: Double = 0.35
        /// What a second broken word directly under the first costs on top of it.
        static let doubleHyphenPenalty: Double = 1.5
        /// What breaking a tie costs, so the pair the binder held comes apart only where it earns it.
        static let tiePenalty: Double = 0.7
        /// The least a paragraph's last line may hold before it reads as a stub, against the measure.
        static let shortestLastLine: CGFloat = 0.16
        static let shortLastLinePenalty: Double = 1.4

        /// How much of a character may sit outside the measure, against its own width.
        ///
        /// A hyphen is a bar through the middle of a wide blank, so most of it hangs. A full stop and a
        /// comma sit low and small and hang nearly as far. A question mark is tall and dark enough to
        /// read as part of the edge, so it barely moves.
        static let hangs: [Character: CGFloat] = [
            "-": 0.6, "\u{2010}": 0.6, "–": 0.45, "—": 0.3,
            ".": 0.55, ",": 0.55, "…": 0.3, ":": 0.35, ";": 0.4,
            "!": 0.25, "?": 0.2,
            "»": 0.3, "”": 0.35, "’": 0.45, "\"": 0.35, "'": 0.45, ")": 0.15, "]": 0.15,
        ]
    }

    /// One line as the column settled it, ready to be cut into a page and drawn.
    struct Line {
        var characters: NSRange
        var startsParagraph: Bool
        var endsParagraph: Bool
        /// The line ends in the middle of a word, so a hyphen stands at the end of it.
        var endsWithHyphen: Bool
        var isHeading: Bool
        var isJustified: Bool
        /// How deep the line stands, the space under it included.
        var height: CGFloat
        /// Where the line's baseline sits below its own top.
        var baseline: CGFloat
        /// Where the line's ink begins, from the left edge of the text.
        var origin: CGFloat
        /// How wide the line's ink runs.
        var width: CGFloat
        var drawn: CTLine?
        /// The picture the line stands for, on a line that is one instead of text.
        var image: PageImage?
        /// How large that picture is drawn, from the line's own top left corner.
        var imageSize: CGSize = .zero
        /// Why the column left the line short, where it did.
        var shortReason: String?
        /// How far the line's gaps stand open, against the width the font gives a space.
        var gapMultiple: CGFloat = 1
        /// How many gaps the line had to open, which is all it could fill itself from.
        var gaps: Int = 0
    }

    private let measure: CGFloat
    /// How deep a page runs, which is as tall as a picture may be set.
    private let depth: CGFloat
    private let headingLength: Int
    /// How wide each hanging mark is in each face the chapter uses, so the breaker measures none twice.
    private var hangWidths: [UIFont: [Character: CGFloat]] = [:]

    private init(measure: CGFloat, depth: CGFloat, headingLength: Int) {
        self.measure = measure
        self.depth = depth
        self.headingLength = headingLength
    }

    /// Sets a whole chapter, a paragraph at a time.
    static func compose(
        text: NSAttributedString,
        headingLength: Int,
        measure: CGFloat,
        depth: CGFloat,
        onProgress: (@MainActor (Double) -> Void)?
    ) async -> [Line] {
        let composer = ColumnComposer(measure: measure, depth: depth, headingLength: headingLength)
        let string = text.string as NSString
        var paragraphs: [NSRange] = []
        var start = 0

        for index in 0 ..< string.length where string.character(at: index) == 0x0A {
            paragraphs.append(NSRange(location: start, length: index - start + 1))
            start = index + 1
        }

        if start < string.length {
            paragraphs.append(NSRange(location: start, length: string.length - start))
        }

        var result: [Line] = []

        for (index, range) in paragraphs.enumerated() {
            if let picture = text.attribute(.pageImage, at: range.location, effectiveRange: nil) as? PageImage {
                result.append(composer.line(of: picture, in: text, range: range))
            } else if let ruler = ParagraphRuler(text: text, range: range) {
                result.append(contentsOf: composer.lines(of: ruler))
            }

            if index % 8 == 7 {
                onProgress?(Double(index + 1) / Double(paragraphs.count))
                await Task.yield()
            }
        }

        onProgress?(1)
        return result
    }

    // MARK: - Setting one paragraph

    private func lines(of ruler: ParagraphRuler) -> [Line] {
        let isHeading = ruler.range.location < headingLength

        guard !ruler.isBlank else { return [ blank(ruler, isHeading: isHeading) ] }

        let stops = chooseStops(ruler)

        return (0 ..< stops.count - 1).map { step in
            let piece = candidate(
                ruler,
                from: stops[step].position,
                at: stops[step + 1],
                isFirst: step == 0,
                isLast: step == stops.count - 2
            )

            return draw(piece, ruler: ruler, isHeading: isHeading)
        }
    }

    /// A picture as one line of the column, as deep as it is drawn and centred in the measure.
    ///
    /// It takes the whole measure where it is wide enough for it, and no more of the page than the page
    /// has, so a plate too tall to share one always lands on a page of its own rather than running off
    /// the foot of it.
    private func line(of picture: PageImage, in text: NSAttributedString, range: NSRange) -> Line {
        let style = text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        let spacing = (style?.lineSpacing ?? 0) + (style?.paragraphSpacing ?? 0)
        let size = picture.size(fitting: measure, depth: max(1, depth - spacing))

        return Line(
            characters: range,
            startsParagraph: true,
            endsParagraph: true,
            endsWithHyphen: false,
            isHeading: false,
            isJustified: false,
            height: size.height + spacing,
            baseline: 0,
            origin: (measure - size.width) / 2,
            width: size.width,
            image: picture,
            imageSize: size
        )
    }

    /// A paragraph with nothing in it, which is how the space under a heading is filed.
    private func blank(_ ruler: ParagraphRuler, isHeading: Bool) -> Line {
        Line(
            characters: ruler.range,
            startsParagraph: true,
            endsParagraph: true,
            endsWithHyphen: false,
            isHeading: isHeading,
            isJustified: false,
            height: ruler.font.lineHeight + ruler.lineSpacing + ruler.paragraphSpacing,
            baseline: ruler.font.ascender,
            origin: 0,
            width: 0
        )
    }

    /// Where a line may start, with what the break before it did to the line above.
    private struct Stop {
        var position: Int
        var hyphenates = false
        var drawsHyphen = false
        var tied = false
    }

    /// One candidate line, measured and with its slack already shared out.
    private struct Candidate {
        var start: Int
        var ending: Int
        var content: Int
        var natural: CGFloat
        var available: CGFloat
        var slack: CGFloat
        var squeezeCapacity: CGFloat
        var gaps: Int
        var letters: Int
        var holdsFirstGap: Bool
        var drawsHyphen: Bool
        var hyphenates: Bool
        var isJustified: Bool
        var isLast: Bool
        var indent: CGFloat
        var fill: LineFill

        /// True where the line is meant to reach the measure rather than stop where its words stop.
        var fills: Bool { isJustified && !isLast }
    }

    private func candidate(
        _ ruler: ParagraphRuler,
        from start: Int,
        at stop: Stop,
        isFirst: Bool,
        isLast: Bool
    ) -> Candidate {
        let content = ruler.content(from: start, to: stop.position)
        let natural = ruler.width(from: start, to: content) + (stop.drawsHyphen ? ruler.hyphenWidth : 0)
        let isJustified = ruler.alignment == .justified
        let fills = isJustified && !isLast
        let holdsFirstGap = isFirst && Self.opensOnDash(ruler)
        let drawn = ruler.characters(from: start, to: content) + (stop.drawsHyphen ? 1 : 0)
        let indent = isFirst ? ruler.firstLineIndent : 0
        let hang = fills ? hang(ruler, at: content, drawsHyphen: stop.drawsHyphen) : 0
        let available = measure - indent + hang
        let slack = available - natural
        let gaps = max(0, ruler.gaps(from: start, to: content) - (holdsFirstGap ? 1 : 0))
        let letters = max(0, drawn - 1 - (holdsFirstGap ? 1 : 0))
        let squeeze = isJustified
            ? CGFloat(gaps) * ruler.spaceWidth * Rules.gapSqueeze
                + CGFloat(letters) * ruler.font.pointSize * Rules.letterSqueeze
            : 0
        var fill = LineFill()

        if isJustified, slack < 0 || fills {
            fill = LineFill.solve(
                slack: slack,
                in: LineFill.Room(
                    gaps: gaps,
                    letters: letters,
                    inkWidth: natural,
                    spaceWidth: ruler.spaceWidth,
                    fontSize: ruler.font.pointSize,
                    widensGlyphs: fills
                )
            )
        }

        return Candidate(
            start: start,
            ending: stop.position,
            content: content,
            natural: natural,
            available: available,
            slack: slack,
            squeezeCapacity: squeeze,
            gaps: gaps,
            letters: letters,
            holdsFirstGap: holdsFirstGap,
            drawsHyphen: stop.drawsHyphen,
            hyphenates: stop.hyphenates,
            isJustified: isJustified,
            isLast: isLast,
            indent: indent,
            fill: fill
        )
    }

    // MARK: - Choosing where the lines break

    /// Every arrangement of a paragraph's breaks costed, and the cheapest kept.
    ///
    /// Filling each line as full as it will go is what leaves the line before a long word standing wide
    /// open, since every line is taken without regard for the one after it. Costing the paragraph whole
    /// lets a line give a word up so that it and the one below it read as one setting.
    private func chooseStops(_ ruler: ParagraphRuler) -> [Stop] {
        var stops = [ Stop(position: 0) ]

        for opportunity in ruler.breaks {
            stops.append(Stop(
                position: opportunity.position,
                hyphenates: opportunity.hyphenates,
                drawsHyphen: opportunity.drawsHyphen,
                tied: opportunity.tied
            ))
        }

        stops.append(Stop(position: ruler.length))

        var best = [Double](repeating: .infinity, count: stops.count)
        var came = [Int](repeating: 0, count: stops.count)
        best[0] = 0

        for stop in 1 ..< stops.count {
            let isLast = stop == stops.count - 1

            for previous in stride(from: stop - 1, through: 0, by: -1) {
                let piece = candidate(
                    ruler,
                    from: stops[previous].position,
                    at: stops[stop],
                    isFirst: previous == 0,
                    isLast: isLast
                )

                // Reaching further back only makes the line longer, so once it cannot be closed up
                // enough to fit, nothing before it will fit either. The nearest break always stands, so
                // a word wider than the measure still lands somewhere.
                if previous < stop - 1, -piece.slack > piece.squeezeCapacity { break }

                guard best[previous] < .infinity else { continue }

                var total = best[previous] + cost(piece, ruler: ruler)

                if stops[stop].tied { total += Rules.tiePenalty }

                if stops[stop].hyphenates {
                    total += Rules.hyphenPenalty

                    if stops[previous].hyphenates { total += Rules.doubleHyphenPenalty }
                }

                if total < best[stop] {
                    best[stop] = total
                    came[stop] = previous
                }
            }
        }

        var chosen: [Stop] = []
        var stop = stops.count - 1

        while stop > 0 {
            chosen.append(stops[stop])
            stop = came[stop]
        }

        chosen.append(stops[0])
        chosen.reverse()
        return chosen
    }

    /// What one line costs: how hard it has to be pushed to fill, and what it leaves behind if it can't.
    private func cost(_ piece: Candidate, ruler: ParagraphRuler) -> Double {
        let space = max(1, ruler.spaceWidth)

        // Too wide for its measure. Only a justified line may close up, and only so far.
        if piece.slack < 0 {
            let unclosed = piece.isJustified ? -piece.fill.shortfall : -piece.slack

            guard unclosed <= 0.01 else { return Rules.overrunPenalty * Double(unclosed / space) }

            return Rules.squeezePenalty * Double(piece.fill.reach * piece.fill.reach)
        }

        guard !piece.isLast else { return lastLineCost(piece) }
        guard
            piece.fills
        else {
            // Nothing fills a ragged line, so what is left on it is simply how uneven the edge reads.
            let loose = Double(piece.slack / max(1, piece.available))
            return Rules.raggedPenalty * loose * loose
        }

        let reach = Double(piece.fill.reach)
        let openedBy = max(0, Double(piece.fill.perGap / space) - Rules.gapStretch)
        let short = Double(piece.fill.shortfall / space)
        let widened = Double((piece.fill.glyphScale - 1) / Rules.glyphStretch)

        return reach * reach
            + Rules.openGapPenalty * openedBy * openedBy
            + widened
            + Rules.shortPenalty * short * short
    }

    /// A paragraph's last line takes whatever is left, but a stub of one reads as a mistake.
    private func lastLineCost(_ piece: Candidate) -> Double {
        let least = measure * Rules.shortestLastLine

        guard piece.start > 0, piece.natural < least else { return 0 }

        let missing = Double((least - piece.natural) / least)
        return Rules.shortLastLinePenalty * missing * missing
    }

    // MARK: - Setting a chosen line

    private func draw(_ piece: Candidate, ruler: ParagraphRuler, isHeading: Bool) -> Line {
        var fill = piece.fill
        var drawn = ruler.setting(
            from: piece.start,
            to: piece.content,
            fill: fill,
            holdsFirstGap: piece.holdsFirstGap,
            drawsHyphen: piece.drawsHyphen
        )
        var width = Self.width(of: drawn)

        // The gaps take up whatever the arithmetic and the shaping disagree about, so the column's edge
        // is the edge rather than nearly it.
        if piece.fills, piece.gaps > 0, fill.shortfall <= 0.01, abs(piece.available - width) > 0.05 {
            fill.perGap += (piece.available - width) / CGFloat(piece.gaps)
            drawn = ruler.setting(
                from: piece.start,
                to: piece.content,
                fill: fill,
                holdsFirstGap: piece.holdsFirstGap,
                drawsHyphen: piece.drawsHyphen
            )
            width = Self.width(of: drawn)
        }

        let origin =
            ruler.alignment == .center
            ? piece.indent + (measure - piece.indent - width) / 2
            : piece.indent

        return Line(
            characters: NSRange(location: ruler.range.location + piece.start, length: piece.ending - piece.start),
            startsParagraph: piece.start == 0,
            endsParagraph: piece.isLast,
            endsWithHyphen: piece.hyphenates,
            isHeading: isHeading,
            isJustified: piece.isJustified,
            height: ruler.font.lineHeight + ruler.lineSpacing + (piece.isLast ? ruler.paragraphSpacing : 0),
            baseline: ruler.font.ascender,
            origin: origin,
            width: width,
            drawn: drawn,
            shortReason: piece.fills ? Self.reason(fill, piece: piece, ruler: ruler) : nil,
            gapMultiple: piece.gaps > 0 ? 1 + fill.perGap / max(1, ruler.spaceWidth) : 1,
            gaps: piece.gaps
        )
    }

    private static func width(of line: CTLine?) -> CGFloat {
        line.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) } ?? 0
    }

    private static func reason(_ fill: LineFill, piece: Candidate, ruler: ParagraphRuler) -> String? {
        guard fill.shortfall > 0.5 else { return nil }
        guard piece.gaps > 0 else { return "nothing on the line to open" }

        return String(
            format: "%.0fpt short with the gaps at %.1f× and the letters %.2fpt apart",
            fill.shortfall,
            1 + fill.perGap / max(1, ruler.spaceWidth),
            fill.perLetter
        )
    }

    // MARK: - What the column holds back

    /// True where the paragraph opens on the dash of speech, whose gap keeps the width the font gives it.
    ///
    /// That dash stands at the column's left edge as much as the margin does, and opening the gap after
    /// it lands the first letter somewhere different in every paragraph.
    private static func opensOnDash(_ ruler: ParagraphRuler) -> Bool {
        guard ruler.length > 1, isDash(ruler.character(at: 0)) else { return false }

        return ruler.character(at: 1) == 0x20
    }

    private static func isDash(_ character: unichar) -> Bool {
        character == 0x2014 || character == 0x2013 || character == 0x2015 || character == 0x002D
    }

    /// How far the last character of a line is set outside the measure.
    ///
    /// A justified column is a straight edge of letters, and a line ending in a hyphen or a comma stops
    /// short of it: those marks are mostly the white space around them, so the eye reads the edge as
    /// notched wherever one lands.
    private func hang(_ ruler: ParagraphRuler, at content: Int, drawsHyphen: Bool) -> CGFloat {
        var mark: Character?

        if drawsHyphen {
            mark = "-"
        } else if let scalar = Unicode.Scalar(ruler.character(at: content - 1)) {
            mark = Character(scalar)
        }

        guard let mark, let fraction = Rules.hangs[mark] else { return 0 }

        return widths(for: ruler.font)[mark].map { $0 * fraction } ?? 0
    }

    private func widths(for font: UIFont) -> [Character: CGFloat] {
        if let known = hangWidths[font] { return known }

        let measured = Rules.hangs.keys.reduce(into: [Character: CGFloat]()) { result, mark in
            result[mark] = String(mark).size(withAttributes: [ .font: font ]).width
        }

        hangWidths[font] = measured
        return measured
    }
}
