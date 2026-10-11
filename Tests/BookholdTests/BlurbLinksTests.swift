//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import Testing

@testable import Bookhold

/// Which stretches of a blurb open in the browser. Every word and address here is invented.
struct BlurbLinksTests {
    @Test
    func linksAWebAddressAndNothingAroundIt() throws {
        let blurb = BookFormatting.blurb("<p>Мурлы кваз https://example.com/work/12 дрын.</p><p>Фыр</p>")
        let linked = blurb.runs.filter { $0.link != nil }
        let run = try #require(linked.first)

        #expect(linked.count == 1)
        #expect(run.link == URL(string: "https://example.com/work/12"))
        #expect(String(blurb[run.range].characters) == "https://example.com/work/12")
        #expect(String(blurb.characters) == "Мурлы кваз https://example.com/work/12 дрын.\n\nФыр")
    }

    @Test
    func leavesAMailAddressAsText() {
        let blurb = BookFormatting.blurb("<p>Кваз nobody@example.com дрын</p>")

        #expect(blurb.runs.allSatisfy { $0.link == nil })
    }
}
