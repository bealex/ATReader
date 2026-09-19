//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import CoreGraphics
import Foundation

/// Cuts one page out of a stretch of a chapter's lines, forwards from where the page starts or
/// backwards from where it ends.
///
/// Only the lines near a page are composed, so the page is chosen against the few pages beside it
/// rather than against the whole chapter. Every run of breaks over the stretch is costed, a page's
/// shortfall counted in lines and squared, and the page at the near end of the cheapest run is the one
/// cut. Squaring shares a loss out between pages instead of leaving the page a rule bit to pay all of
/// it, and breaking a rule costs so much more than any unevenness that the rules still decide where a
/// page may break.
struct PageCutter: Sendable {
    /// One line, flattened to what the cutting reads.
    ///
    /// A `ColumnComposer.Line` carries a picture and a string, so each of the many reads the search
    /// makes would be two reference counts on top of the comparison it came for.
    struct Slug: Sendable {
        var characters: NSRange
        /// How deep the line stands, the space under it included.
        var height: CGFloat
        /// The least it may stand at. The same as `height` for text, which gives up nothing; a plate
        /// may give up some of its own depth to finish the page it stands on.
        var leastHeight: CGFloat
        /// How much air stands above the line, where it opens a title block.
        var titleAir: CGFloat
        var startsParagraph: Bool
        var endsParagraph: Bool
        var endsWithHyphen: Bool
        var isHeading: Bool
        var isImage: Bool
        /// The line divides the scene above it from the one below, so no page may open on it.
        var isSceneBreak: Bool = false
    }

    let slugs: [Slug]
    /// How deep a full page runs.
    let depth: CGFloat
    /// A line of the heading's own type, which is the air a title has to keep to be worth a page break.
    let pageLine: CGFloat
    /// The depth of an ordinary line of the body, which is the unit a page's shortfall is counted in.
    let referenceLineHeight: CGFloat
    /// The slugs run to the chapter's last line, so a page ending with them ends the chapter.
    var reachesEnd = true
    /// The slugs start at the chapter's first line.
    var reachesStart = true

    /// How many pages past the one being cut the search looks at, which is how far a loss is shared.
    static let lookahead: CGFloat = 2

    // MARK: - Where a page breaks

    /// Where the page starting at slug `start` ends, `room` deep.
    ///
    /// Past the last slug the chapter goes on where the slugs don't reach its end, so a run may stop on
    /// any page the remaining slugs would fit on: that page is finished by lines nobody has composed.
    func end(from start: Int, room: CGFloat) -> Int {
        let count = slugs.count
        let sums = runningDepths
        var best = [Double](repeating: .infinity, count: count + 1)

        if reachesEnd { best[count] = 0 }

        for next in stride(from: count - 1, to: start, by: -1) {
            if !reachesEnd, fits(next ..< count, sums: sums, in: depth) {
                best[next] = 0
                continue
            }

            best[next] = cheapestPage(from: next, room: depth, best: best).cost
        }

        return cheapestPage(from: start, room: room, best: best).limit
    }

    /// Where the page ending at slug `limit` starts, `room` deep.
    ///
    /// The mirror of ``end(from:room:)``. A page that opens the chapter may come out short, since that
    /// is where a chapter read from behind begins: its lines stand at the foot of the page, and the
    /// pages after it stay full.
    func start(to limit: Int, room: CGFloat) -> Int {
        guard limit > 1 else { return 0 }

        let sums = runningDepths
        var best = [Double](repeating: .infinity, count: limit + 1)

        if reachesStart { best[0] = 0 }

        for end in 1 ..< limit {
            // A page ending here that the slugs would fit on is finished above them. The break at its
            // foot still answers to the rules, since that break is one the reader sees.
            if !reachesStart, fits(0 ..< end, sums: sums, in: depth) {
                best[end] = Double(brokenRules(breakingAt: end, from: 0)) * ChapterLayout.Rules.brokenRule
                continue
            }

            best[end] = cheapestPage(to: end, room: depth, best: best).cost
        }

        return cheapestPage(to: limit, room: room, best: best).start
    }

    private func cheapestPage(from start: Int, room: CGFloat, best: [Double]) -> (cost: Double, limit: Int) {
        typealias Rules = ChapterLayout.Rules

        var chosen = (cost: Double.infinity, limit: start + 1)
        var used: CGFloat = 0
        var limit = start + 1

        while limit <= slugs.count {
            used += slugs[limit - 1].height
            let squeeze = CGFloat(limit - start - 1) * Rules.tightening
            let filled = fitting(used, over: start ..< limit, in: room + squeeze)

            // Nothing longer will fit. One line always may, so a line taller than the page still lands
            // on one instead of leaving the chapter with nowhere to break.
            if filled == nil, limit > start + 1 { break }

            let total = cost(from: start, to: limit, available: room, used: filled ?? used) + best[limit]

            if total < chosen.cost { chosen = (total, limit) }

            limit += 1
        }

        return chosen
    }

    private func cheapestPage(to limit: Int, room: CGFloat, best: [Double]) -> (cost: Double, start: Int) {
        typealias Rules = ChapterLayout.Rules

        var chosen = (cost: Double.infinity, start: limit - 1)
        var used: CGFloat = 0
        var start = limit - 1

        while start >= 0 {
            used += slugs[start].height
            let squeeze = CGFloat(limit - start - 1) * Rules.tightening
            let filled = fitting(used, over: start ..< limit, in: room + squeeze)

            if filled == nil, start < limit - 1 { break }

            let opens = reachesStart && start == 0
            let total = best[start] + cost(from: start, to: limit, available: room, used: filled ?? used, opens: opens)

            if total < chosen.cost { chosen = (total, start) }

            start -= 1
        }

        return chosen
    }

    /// How deep the slugs before each index stand, so a stretch's depth is a subtraction.
    private var runningDepths: [CGFloat] {
        var sums = [CGFloat](repeating: 0, count: slugs.count + 1)

        for index in slugs.indices { sums[index + 1] = sums[index] + slugs[index].height }

        return sums
    }

    private func fits(_ lines: Range<Int>, sums: [CGFloat], in room: CGFloat) -> Bool {
        let used = sums[lines.upperBound] - sums[lines.lowerBound]
        let squeeze = CGFloat(max(0, lines.count - 1)) * ChapterLayout.Rules.tightening

        return fitting(used, over: lines, in: room + squeeze) != nil
    }

    /// How deep the page over `lines` actually stands, letting the plate nearest its foot give up depth
    /// to finish it. Nil where not even that plate's floor will fit, which is where a page has to break
    /// earlier.
    ///
    /// The plate is not always the last line: a scene break closing the passage can stand under it, so
    /// the page is searched for one rather than only asking whatever happens to be at the foot.
    private func fitting(_ used: CGFloat, over lines: Range<Int>, in room: CGFloat) -> CGFloat? {
        guard used > room else { return used }
        guard let plate = givingPlate(in: lines) else { return nil }

        let canGive = slugs[plate].height - slugs[plate].leastHeight

        guard used - room <= canGive else { return nil }

        return room
    }

    /// The plate nearest the foot of a page with depth to spare, where the page carries one.
    private func givingPlate(in lines: Range<Int>) -> Int? {
        lines.reversed().first { slugs[$0].isImage && slugs[$0].height > slugs[$0].leastHeight }
    }

    /// What one page costs: the rules it breaks, and how far short of its measure it comes.
    ///
    /// A page ending the chapter stops where the text stops, and one opening it reached from behind
    /// stands at the foot of its page, so neither is short of anything; only a stub of one is a fault.
    private func cost(
        from start: Int,
        to limit: Int,
        available: CGFloat,
        used: CGFloat,
        opens: Bool = false
    ) -> Double {
        typealias Rules = ChapterLayout.Rules

        let count = limit - start
        let endsTheChapter = reachesEnd && limit == slugs.count
        var penalty = Double(brokenRules(breakingAt: limit, from: start)) * Rules.brokenRule

        if count < Rules.minimumLines, !endsTheChapter { penalty += Rules.brokenRule }

        guard
            !endsTheChapter,
            !opens
        else {
            return penalty + Double(max(0, Rules.shortLastPage + 1 - count)) * Rules.thinLastPage
        }

        let short = Double((available - used) / referenceLineHeight)
        return penalty + short * short
    }

    /// How many of a compositor's rules breaking here would break.
    private func brokenRules(breakingAt limit: Int, from start: Int) -> Int {
        // The end of the slugs is where the text stops, or where nobody has composed on from, and
        // neither is a break that has to answer for itself.
        guard limit < slugs.count, limit > 0 else { return 0 }

        let last = slugs[limit - 1]
        let following = slugs[limit]
        var broken = 0

        // A page cannot end on a broken word.
        if last.endsWithHyphen { broken += 1 }

        // An orphan: the first line of a paragraph, alone at the foot of the page.
        if last.startsParagraph, !last.endsParagraph { broken += 1 }

        // A widow: the last line of a paragraph, alone at the top of the next one.
        if following.endsParagraph, !following.startsParagraph { broken += 1 }

        // A scene break divides what stands above it from what stands below. At the head of a page the
        // page break has already done the dividing, so the mark says nothing there and belongs at the
        // foot of the page it closes.
        if following.isSceneBreak { broken += 1 }

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

    /// The page over `lines`, with its spare room shared out.
    ///
    /// A page that ends the chapter keeps its ragged foot: the text stops where the chapter stops. One
    /// that opens the chapter from behind and is short of more than its gaps can take up sinks instead,
    /// its lines standing at the foot so they run straight on to the page after it.
    func page(_ lines: Range<Int>, room: CGFloat, endsTheChapter: Bool, opensTheChapter: Bool) -> ChapterLayout.Page {
        typealias Rules = ChapterLayout.Rules

        var page = ChapterLayout.Page(lines: lines)

        page.plate = plate(on: page, available: room)

        let spread = spacing(for: page, available: room, endsTheChapter: endsTheChapter)
        let gaps = CGFloat(max(0, lines.count - 1))
        let used = lines.reduce(CGFloat(0)) { $0 + depth(of: $1, on: page) }
        let sinks = opensTheChapter && !endsTheChapter && room - used > gaps * Rules.loosening

        guard
            !sinks
        else {
            page.top = room - used
            return page
        }

        page.leading = spread.leading
        page.imagePadding = spread.imagePadding
        return page
    }

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
        let used = page.lines.reduce(CGFloat(0)) { $0 + depth(of: $1, on: page) }
        let slack = available - used
        // Everywhere but the end of a chapter the lines take their share first, so a page of text
        // carrying a picture comes down to the same depth as every other page.
        let leading =
            endsTheChapter || gaps <= 0
            ? 0
            : min(max(slack / CGFloat(gaps), -Rules.tightening), Rules.loosening)
        let pictures = picturesTakingTheRoom(on: page, endsTheChapter: endsTheChapter)

        guard pictures > 0, slack > 0 else { return Spacing(leading: leading) }

        // Whatever no amount of leading could absorb is the pictures'.
        return Spacing(leading: leading, imagePadding: (slack - leading * CGFloat(gaps)) / CGFloat(2 * pictures))
    }

    /// What the plate at the foot of a page gave up to finish it, where it had to give anything.
    ///
    /// A plate standing alone on a page is left as it is: it already has the whole page, and one too
    /// tall for even that gave up width when it was measured.
    private func plate(on page: ChapterLayout.Page, available: CGFloat) -> ChapterLayout.Page.Plate? {
        typealias Rules = ChapterLayout.Rules

        guard page.lines.count > 1, let plate = givingPlate(in: page.lines) else { return nil }

        let used = page.lines.reduce(CGFloat(0)) { $0 + slugs[$1].height }
        let room = available + CGFloat(page.lines.count - 1) * Rules.tightening

        guard used > room else { return nil }

        let given = min(used - room, slugs[plate].height - slugs[plate].leastHeight)

        guard given > 0 else { return nil }

        return ChapterLayout.Page.Plate(line: plate, height: slugs[plate].height - given)
    }

    /// How deep a line stands on a page, which is less than its own depth for a plate that gave some up.
    private func depth(of line: Int, on page: ChapterLayout.Page) -> CGFloat {
        guard let plate = page.plate, plate.line == line else { return slugs[line].height }

        return plate.height
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
            leastHeight: image == nil ? height : height - imageSize.height * ChapterLayout.Rules.plateGivesUp,
            titleAir: titleAir,
            startsParagraph: startsParagraph,
            endsParagraph: endsParagraph,
            endsWithHyphen: endsWithHyphen,
            isHeading: isHeading,
            isImage: image != nil,
            isSceneBreak: isSceneBreak
        )
    }
}
