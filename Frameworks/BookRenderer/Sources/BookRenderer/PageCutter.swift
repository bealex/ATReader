//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import CoreGraphics
import Foundation

/// Cuts a chapter's column into pages.
///
/// All of it is arithmetic over one line's depth and the handful of things a rule asks about a line,
/// so it takes a flattened copy of the column and runs away from the main actor. Cutting a chapter
/// there is what took the gestures off the reader while the book behind them was being measured.
struct PageCutter: Sendable {
    /// One line, flattened to what the cutting reads.
    ///
    /// A `ColumnComposer.Line` carries a picture and a string, so each of the hundreds of thousands of
    /// reads the search makes would be two reference counts on top of the comparison it came for.
    struct Slug: Sendable {
        var characters: NSRange
        /// How deep the line stands, the space under it included.
        var height: CGFloat
        /// How much air stands above the line, where it opens a title block.
        var titleAir: CGFloat
        var startsParagraph: Bool
        var endsParagraph: Bool
        var endsWithHyphen: Bool
        var isHeading: Bool
        var isImage: Bool
    }

    /// Where the pages fall and what each one covers.
    struct Cut: Sendable {
        var pages: [ChapterLayout.Page] = []
        var ranges: [NSRange] = []
    }

    let slugs: [Slug]
    /// How deep a full page runs.
    let depth: CGFloat
    /// What the chapter before this one already used on its first page.
    let startOffset: CGFloat
    /// A line of the heading's own type, which is the air a title has to keep to be worth a page break.
    let pageLine: CGFloat
    /// The depth of an ordinary line of the body, which is the unit a page's shortfall is counted in.
    let referenceLineHeight: CGFloat

    /// The cut, made off the main actor.
    func away() async -> Cut {
        guard !slugs.isEmpty else { return Cut() }

        return await Task.detached(priority: .userInitiated) { cut() }.value
    }

    func cut() -> Cut {
        guard !slugs.isEmpty else { return Cut() }

        var cut = Cut()
        var start = 0

        for limit in chooseBreaks() {
            cut.pages.append(ChapterLayout.Page(lines: start ..< limit, leading: 0))
            start = limit
        }

        for index in cut.pages.indices {
            let spread = spacing(
                for: cut.pages[index],
                available: height(ofPageAt: index),
                endsTheChapter: index == cut.pages.count - 1
            )

            cut.pages[index].leading = spread.leading
            cut.pages[index].imagePadding = spread.imagePadding
        }

        cut.ranges = cut.pages.map { page in
            let first = slugs[page.lines.lowerBound].characters
            let last = slugs[page.lines.upperBound - 1].characters

            return NSRange(location: first.location, length: last.location + last.length - first.location)
        }

        return cut
    }

    private func height(ofPageAt index: Int) -> CGFloat {
        depth - (index == 0 ? startOffset : 0)
    }

    /// The depth of a page starting on a given line. Only a chapter's first page is ever short, and only
    /// where the chapter before it left it something.
    private func capacity(startingAt line: Int) -> CGFloat {
        depth - (line == 0 ? startOffset : 0)
    }

    // MARK: - Where the pages break

    /// Where every page of the chapter breaks, chosen so the pages come out the same depth.
    ///
    /// Filling each page in turn and handing whatever a rule rejects to the next one is what left a page
    /// four lines short between two full ones: wherever the rule bit, that page paid all of it. So every
    /// run of breaks is costed instead, a page's shortfall counted in lines and squared, and the cheapest
    /// run wins. Squaring is what shares the loss out, since one line missing from each of four pages
    /// costs a quarter of what four missing from one does.
    ///
    /// The rules are not traded against depth. Breaking one costs so much more than any unevenness that
    /// they still decide where a page may break, and evenness only chooses among the breaks they allow.
    private func chooseBreaks() -> [Int] {
        typealias Rules = ChapterLayout.Rules

        let count = slugs.count
        var best = [Double](repeating: .infinity, count: count + 1)
        var next = [Int](repeating: count, count: count + 1)
        best[count] = 0

        for start in stride(from: count - 1, through: 0, by: -1) {
            let available = capacity(startingAt: start)
            var used: CGFloat = 0
            var limit = start + 1

            while limit <= count {
                used += slugs[limit - 1].height
                let squeeze = CGFloat(limit - start - 1) * Rules.tightening

                // Nothing longer will fit. One line always may, so a line taller than the page still
                // lands on one instead of leaving the chapter with nowhere to break.
                if used > available + squeeze, limit > start + 1 { break }

                let total = cost(from: start, to: limit, available: available, used: used) + best[limit]

                if total < best[start] {
                    best[start] = total
                    next[start] = limit
                }

                limit += 1
            }
        }

        var breaks: [Int] = []
        var start = 0

        while start < count {
            let limit = next[start]

            guard limit > start else { break }

            breaks.append(limit)
            start = limit
        }

        return breaks
    }

    /// What one page costs: the rules it breaks, and how far short of its measure it comes.
    private func cost(from start: Int, to limit: Int, available: CGFloat, used: CGFloat) -> Double {
        typealias Rules = ChapterLayout.Rules

        let count = limit - start
        let endsTheChapter = limit == slugs.count
        var penalty = Double(brokenRules(breakingAt: limit, from: start)) * Rules.brokenRule

        if count < Rules.minimumLines, !endsTheChapter { penalty += Rules.brokenRule }

        guard
            !endsTheChapter
        else {
            // A chapter ending in a line or two on a page of its own reads as a mistake, so the page
            // before it is worth shortening to feed it.
            return penalty + Double(max(0, Rules.shortLastPage + 1 - count)) * Rules.thinLastPage
        }

        let short = Double((available - used) / referenceLineHeight)
        return penalty + short * short
    }

    /// How many of a compositor's rules breaking here would break.
    private func brokenRules(breakingAt limit: Int, from start: Int) -> Int {
        // The end of the chapter is where the text stops, not a break that has to answer for itself.
        guard limit < slugs.count else { return 0 }

        let last = slugs[limit - 1]
        let following = slugs[limit]
        var broken = 0

        // A page cannot end on a broken word.
        if last.endsWithHyphen { broken += 1 }

        // An orphan: the first line of a paragraph, alone at the foot of the page.
        if last.startsParagraph, !last.endsParagraph { broken += 1 }

        // A widow: the last line of a paragraph, alone at the top of the next one.
        if following.endsParagraph, !following.startsParagraph { broken += 1 }

        // A title stands in its own air, and at the head of a page that air falls off the top with
        // nothing left to say. Only a title given enough of it to notice: the smallest levels keep a
        // single line, which is no loss.
        if following.titleAir >= pageLine * 3 { broken += 1 }

        // A heading belongs with the text it introduces.
        if headingStranded(breakingAt: limit, from: start) { broken += 1 }

        return broken
    }

    /// True when the page ends on a heading, or with too little of its chapter under it.
    private func headingStranded(breakingAt limit: Int, from start: Int) -> Bool {
        typealias Rules = ChapterLayout.Rules

        let tail = max(start, limit - Rules.linesAfterHeading - 1) ..< limit

        guard let heading = tail.last(where: { slugs[$0].isHeading }) else { return false }

        return limit - heading <= Rules.linesAfterHeading
    }

    // MARK: - What is left over

    /// Where a page's spare room goes: between its lines, and around the pictures standing on it.
    private struct Spacing {
        var leading: CGFloat = 0
        var imagePadding: CGFloat = 0
    }

    /// Spreads what is left of the page between its lines, so every page comes down to the same depth
    /// instead of leaving the hole a rule made at its foot.
    private func spacing(for page: ChapterLayout.Page, available: CGFloat, endsTheChapter: Bool) -> Spacing {
        typealias Rules = ChapterLayout.Rules

        let gaps = page.lines.count - 1
        let used = page.lines.reduce(CGFloat(0)) { $0 + slugs[$1].height }
        let slack = available - used
        // A page that ends a chapter keeps its ragged bottom: the text stops where the chapter stops,
        // and opening its gaps would only put air between the last lines the reader sees. Everywhere
        // else the lines take their share first, so a page of text carrying a picture comes down to the
        // same depth as every other page.
        let leading =
            endsTheChapter || gaps <= 0
            ? 0
            : min(max(slack / CGFloat(gaps), -Rules.tightening), Rules.loosening)
        let pictures = picturesTakingTheRoom(on: page, endsTheChapter: endsTheChapter)

        guard pictures > 0, slack > 0 else { return Spacing(leading: leading) }

        // Whatever no amount of leading could absorb is the pictures'.
        return Spacing(leading: leading, imagePadding: (slack - leading * CGFloat(gaps)) / CGFloat(2 * pictures))
    }

    /// How many pictures share what the lines left behind.
    ///
    /// On a page that ends a chapter the spare room stands after the last line rather than being spread
    /// through the page, so only a picture at the end of one has any of that room under it to be
    /// centred in. A picture with the chapter's last words below it already sits where it belongs.
    private func picturesTakingTheRoom(on page: ChapterLayout.Page, endsTheChapter: Bool) -> Int {
        guard endsTheChapter else { return page.lines.count { slugs[$0].isImage } }

        return page.lines.reversed().prefix { slugs[$0].isImage }.count
    }
}

extension ColumnComposer.Line {
    /// What the cutting needs of this line, and nothing it would have to count a reference for.
    var slug: PageCutter.Slug {
        PageCutter.Slug(
            characters: characters,
            height: height,
            titleAir: titleAir,
            startsParagraph: startsParagraph,
            endsParagraph: endsParagraph,
            endsWithHyphen: endsWithHyphen,
            isHeading: isHeading,
            isImage: image != nil
        )
    }
}
