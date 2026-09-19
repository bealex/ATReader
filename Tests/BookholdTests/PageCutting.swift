//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

@testable import BookRenderer

/// A run of lines cut into pages one after another from its first, the way a chapter read from its
/// start is cut.
struct CutPages {
    let pages: [ChapterLayout.Page]
}

extension PageCutter {
    func cutFromTheStart() -> CutPages {
        var pages: [ChapterLayout.Page] = []
        var start = 0

        while start < slugs.count {
            let limit = end(from: start, room: depth)

            pages.append(page(start ..< limit, room: depth, endsTheChapter: limit == slugs.count, opensTheChapter: false))
            start = limit
        }

        return CutPages(pages: pages)
    }
}
