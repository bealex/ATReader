//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import Testing

@testable import BookKit

/// The stretches a formula sets off the line, which the markup gives as `<sub>` and `<sup>`.
///
/// The characters stay exactly as the text gave them, since a reading position is an offset into that
/// text. What the tags leave behind is a range apiece.
struct BookScriptTests {
    private func paragraph(_ html: String) -> Paragraph? {
        BookHTML.paragraphs(from: "<p>\(html)</p>").first
    }

    @Test
    func aLoweredFigureKeepsItsCharacterAndIsMarked() throws {
        let read = try #require(paragraph("H<sub>2</sub>O"))

        #expect(read.text == "H2O")
        #expect(read.scripts.count == 1)
        #expect(read.scripts.first?.range == NSRange(location: 1, length: 1))
        #expect(read.scripts.first?.place == .below)
    }

    @Test
    func aLiftedOneIsMarkedTheOtherWay() throws {
        let read = try #require(paragraph("x<sup>12</sup> и y"))

        #expect(read.text == "x12 и y")
        #expect(read.scripts.first?.range == NSRange(location: 1, length: 2))
        #expect(read.scripts.first?.place == .above)
    }

    @Test
    func severalInOneParagraphStandWhereTheyWereWritten() throws {
        let read = try #require(paragraph("C<sub>2</sub>H<sub>5</sub>OH и CH<sub>3</sub>OH"))

        #expect(read.text == "C2H5OH и CH3OH")
        #expect(read.scripts.map(\.location) == [ 1, 3, 11 ])
        #expect(read.scripts.allSatisfy { $0.place == .below })
    }

    /// The tag as an author wrote it, with an attribute on it and whatever case came to hand.
    @Test
    func theTagIsReadHoweverItIsWritten() throws {
        let read = try #require(paragraph("H<SUB class=\"x\">2</SUB>O"))

        #expect(read.text == "H2O")
        #expect(read.scripts.first?.place == .below)
    }

    @Test
    func anEmptyOneMarksNothing() throws {
        let read = try #require(paragraph("Вода<sub></sub>"))

        #expect(read.text == "Вода")
        #expect(read.scripts.isEmpty)
    }

    @Test
    func aParagraphWithNoneOfThemCarriesNone() throws {
        let read = try #require(paragraph("Обычный абзац без формул."))

        #expect(read.text == "Обычный абзац без формул.")
        #expect(read.scripts.isEmpty)
    }
}
