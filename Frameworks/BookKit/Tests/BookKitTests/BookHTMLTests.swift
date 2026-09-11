//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Testing

@testable import BookKit

/// The fixtures below are generated nonsense — the service's own payloads never enter the repository.
struct BookHTMLTests {
    @Test
    func splitsParagraphsAndDropsMarkup() {
        let html = "<p>Alpha <em>bravo</em> charlie.</p><p>Delta&nbsp;echo &mdash; foxtrot.</p>"
        let paragraphs = BookHTML.paragraphs(from: html)

        #expect(paragraphs.count == 2)
        #expect(paragraphs[0].text == "Alpha bravo charlie.")
        #expect(paragraphs[1].text == "Delta\u{00A0}echo — foxtrot.")
    }

    @Test
    func detectsCenteredParagraphs() {
        let html = "<p style=\"text-align: center;\">Golf hotel</p><p>India juliett</p>"
        let paragraphs = BookHTML.paragraphs(from: html)

        #expect(paragraphs[0].isCentered)
        #expect(!paragraphs[1].isCentered)
    }

    @Test
    func collapsesTheSourcesOwnNewlines() {
        let paragraphs = BookHTML.paragraphs(from: "<p>Kilo\n  Lima\tMike</p>")

        #expect(paragraphs.count == 1)
        #expect(paragraphs[0].text == "Kilo Lima Mike")
    }

    @Test
    func keepsANonBreakingSpace() {
        let paragraphs = BookHTML.paragraphs(from: "<p>Kilo&nbsp;Lima</p>")

        #expect(paragraphs[0].text == "Kilo\u{00A0}Lima")
    }

    @Test
    func joinsTheTextEitherSideOfALineBreak() {
        let paragraphs = BookHTML.paragraphs(from: "<p>Kilo<br>Lima</p>")

        // A newline here would end the paragraph for the typesetter, stranding a short line in the
        // middle of a justified column.
        #expect(paragraphs.count == 1)
        #expect(paragraphs[0].text == "Kilo Lima")
    }

    @Test
    func fallsBackToBareText() {
        let paragraphs = BookHTML.paragraphs(from: "Mike november oscar")

        #expect(paragraphs.count == 1)
        #expect(paragraphs[0].text == "Mike november oscar")
    }

    @Test
    func skipsEmptyParagraphs() {
        let paragraphs = BookHTML.paragraphs(from: "<p></p><p>   </p><p>Papa</p>")

        #expect(paragraphs.count == 1)
        #expect(paragraphs[0].text == "Papa")
    }

    /// A chapter as long as a novel reads in one pass. Looking for the next picture from every paragraph
    /// read the whole rest of a chapter that had none left, once per paragraph, and a novel set as one
    /// chapter took minutes to open.
    @Test
    func aLongChapterWithOnePictureReadsInOnePass() {
        let paragraph = "<p>Жулдыбр кармоздел и вострыня пелькует, трямбла снова кувырнется.</p>"
        let html = "<img src=\"cover.jpg\">" + String(repeating: paragraph, count: 4000)
        let clock = ContinuousClock()

        let took = clock.measure {
            let paragraphs = BookHTML.paragraphs(from: html)

            #expect(paragraphs.count == 4001)
            #expect(paragraphs[0].imageSource == "cover.jpg")
        }

        #expect(took < .seconds(2))
    }
}
