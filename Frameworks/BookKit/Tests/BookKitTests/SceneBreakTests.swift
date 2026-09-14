//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import Testing

@testable import BookKit

/// Which blocks stand for a break in the scene rather than carrying words.
///
/// A page may not open on one, so a block wrongly read as a break is dragged onto the page before it.
/// The test stays narrow for that reason: rows of asterisks and nothing else. The fixtures are
/// generated.
struct SceneBreakTests {
    private func block(_ text: String, titleLevel: Int? = nil, isVerse: Bool = false) -> Paragraph {
        Paragraph(id: 1, text: text, isCentered: true, titleLevel: titleLevel, isVerse: isVerse)
    }

    @Test
    func readsARowOfAsterisksAsABreak() {
        #expect(block("* * *").isSceneBreak)
        #expect(block("***").isSceneBreak)
        #expect(block("*").isSceneBreak)
    }

    @Test
    func takesNoWordsForABreak() {
        #expect(!block("November * oscar").isSceneBreak)
        #expect(!block("Chapter two").isSceneBreak)
        #expect(!block("").isSceneBreak)
        #expect(!block("   ").isSceneBreak)
    }

    /// A title centred on the page is not a break, whatever it is made of, and neither is a plate.
    @Test
    func takesNoTitleOrPlateForABreak() {
        #expect(!block("* * *", titleLevel: 1).isSceneBreak)
        #expect(!block("* * *", isVerse: true).isSceneBreak)
        #expect(!Paragraph(id: 1, text: "* * *", isCentered: true, imageSource: "art.png").isSceneBreak)
    }

    /// A long row of marks is a line of punctuation rather than a break, and moving one would move text.
    @Test
    func takesALongRowOfMarksForOrdinaryText() {
        #expect(!block(String(repeating: "*", count: 40)).isSceneBreak)
    }

    /// The one that centres a break and the one that keeps it off the top of a page are the same test,
    /// so a book cannot have a break by one reading and none by the other.
    @Test
    func agreesWithWhateverCentresABreak() {
        let html = #"<p style="text-align:justify">* * *</p><p style="text-align:justify">November * oscar</p>"#
        let paragraphs = BookHTML.paragraphs(from: html)

        #expect(paragraphs[0].isCentered)
        #expect(paragraphs[0].isSceneBreak)
        #expect(!paragraphs[1].isSceneBreak)
    }
}
