//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Foundation

/// A run of titles standing together, and the air it keeps around itself.
///
/// Titles that touch are one block however many levels they carry: a chapter's number over its name
/// over the name of the part it opens is one thing on the page, not three, so the air goes round the
/// outside of it rather than between its lines.
public enum TitleBlock {
    /// How much air a block keeps above it, counted in lines of the page, by the biggest title in it.
    ///
    /// The block takes the biggest because that is what it announces: a subtitle under a chapter's own
    /// name is part of the chapter opening, and giving it a subtitle's air would close the gap the
    /// chapter opening is supposed to stand in.
    public static func air(forLevel level: Int) -> CGFloat {
        switch level {
            case 1: 12
            case 2: 6
            case 3: 3
            default: 1
        }
    }

    /// What follows a block, counted the same way.
    ///
    /// A block that stands in air is parted from the text under it as well; one that merely breaks the
    /// run of paragraphs is not, since a gap under it and none above would read as belonging to the
    /// text that follows.
    public static func gap(after air: CGFloat) -> CGFloat { air >= 3 ? 2 : 0 }

    /// What is left of a block's air where the block opens a page.
    ///
    /// Not all of it: air at the head of a page has nothing above it to stand clear of, and the twelve
    /// lines a chapter keeps would push its title a third of the way down its own opening page. Not
    /// none of it either, since a title hard against the top edge reads as a page that lost its head.
    public static let atTheTopOfAPage: CGFloat = 2

    /// The strongest title in each block, against the paragraph that opens the block. A paragraph that
    /// is not a title, or that carries on a block already open, answers nothing.
    public static func opening(_ levels: [Int?]) -> [Int?] {
        var opening = [Int?](repeating: nil, count: levels.count)
        var index = 0

        while index < levels.count {
            guard
                levels[index] != nil
            else {
                index += 1
                continue
            }

            var end = index

            while end + 1 < levels.count, levels[end + 1] != nil { end += 1 }

            opening[index] = levels[index ... end].compactMap { $0 }.min()
            index = end + 1
        }

        return opening
    }

    /// True where the paragraph is the last of its block, which is where the gap under it goes.
    public static func closing(_ levels: [Int?]) -> [Bool] {
        levels.indices.map { index in
            levels[index] != nil && (index + 1 == levels.count || levels[index + 1] == nil)
        }
    }
}
