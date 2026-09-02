//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import Testing
import UIKit

@testable import ATReader

/// What a justified column promises: a paragraph is one paragraph however its markup is written, every
/// line inside it reaches the measure, and only the line that ends it stops short.
///
/// The text is generated nonsense. Where a line breaks does not depend on the words meaning anything,
/// and no book's text belongs in this repository.
@MainActor
struct JustificationTests {
    /// How near the measure a line that should fill it has to come, allowing for rounding and for a
    /// mark hung outside the measure.
    static let fills = 0.99

    // MARK: - One paragraph stays one paragraph

    /// The defect this suite was written for. A `<br>` inside a paragraph used to end it, which left
    /// the line before the break unjustified in the middle of a justified column and the text after it
    /// starting a fresh indent.
    @Test(arguments: [ "<br>", "<br/>", "<br />" ])
    func aBreakInsideAParagraphDoesNotSplitIt(tag: String) async {
        let layout = await layout(html: "<p>\(Self.words(40))\(tag)\(Self.words(40))</p>")

        #expect(Self.paragraphEndings(in: layout) == 1, "the break split the paragraph in two")
    }

    /// The source's own newlines are white space to HTML, and used to split the paragraph the same way
    /// a break tag did.
    @Test
    func aNewlineInTheSourceDoesNotSplitAParagraph() async {
        let layout = await layout(html: "<p>\(Self.words(40))\n   \(Self.words(40))</p>")

        #expect(Self.paragraphEndings(in: layout) == 1, "a source newline split the paragraph")
        #expect(Self.shortLines(in: layout).isEmpty)
    }

    @Test
    func aParagraphWithoutBreaksEndsOnce() async {
        let layout = await layout(html: "<p>\(Self.words(80))</p>")

        #expect(Self.paragraphEndings(in: layout) == 1)
    }

    @Test
    func everyParagraphEndsOnce() async {
        let html = (1 ... 4).map { "<p>\(Self.words(30 + $0 * 9))</p>" }.joined()
        let layout = await layout(html: html)

        #expect(Self.paragraphEndings(in: layout) == 4)
    }

    // MARK: - The edge of the column

    @Test
    func everyLineInsideAParagraphReachesTheMeasure() async {
        let layout = await layout(html: "<p>\(Self.words(120))</p>")
        let short = Self.shortLines(in: layout)

        #expect(layout.typesetLines.count > 6, "the paragraph has to run to several lines to say anything")
        #expect(short.isEmpty, "lines stopped short of the measure: \(short)")
    }

    @Test
    func aRunOfParagraphsKeepsItsEdge() async {
        let html = (1 ... 4).map { "<p>\(Self.words(30 + $0 * 9))</p>" }.joined()

        #expect(await Self.shortLines(in: layout(html: html)).isEmpty)
    }

    @Test
    func aBrokenParagraphKeepsItsEdge() async {
        let layout = await layout(html: "<p>\(Self.words(40))<br/>\(Self.words(40))</p>")

        #expect(Self.shortLines(in: layout).isEmpty)
    }

    /// The other half of the promise: a paragraph's own last line is not stretched to the measure.
    @Test
    func theLineThatEndsAParagraphIsLeftShort() async {
        let layout = await layout(html: "<p>\(Self.words(120))</p>")
        let body = layout.typesetLines.filter { !$0.isHeading }

        guard let last = body.last(where: \.endsParagraph) else {
            Issue.record("no paragraph ending found")
            return
        }

        #expect(last.width < Self.measure * Self.fills, "the last line was stretched to the measure")
    }

    // MARK: - Reading the column

    static let measure: CGFloat = 402 - 48

    /// How many paragraphs the column actually set, the heading's own lines aside.
    private static func paragraphEndings(in layout: ChapterLayout) -> Int {
        layout.typesetLines.filter { $0.endsParagraph && !$0.isHeading }.count
    }

    /// Every line that should have reached the measure and did not.
    ///
    /// A paragraph's first line is indented, so its used width is short by the indent and says nothing
    /// about the right edge; its last line is never justified. Both are left out.
    private static func shortLines(in layout: ChapterLayout) -> [String] {
        layout.typesetLines
            .filter { $0.isJustified && !$0.isHeading && !$0.startsParagraph && !$0.endsParagraph }
            .filter { $0.width < measure * fills }
            .map { "\(Int($0.width))pt of \(Int(measure))pt" }
    }

    // MARK: - Building a column

    static var testContext: ChapterLayout.Context {
        ChapterLayout.Context(
            style: ChapterTextStyle(
                face: .serif,
                weight: .regular,
                fontSize: 19,
                lineSpacing: 7,
                letterSpacing: 0,
                justifiesRussian: true,
                justifiesEnglish: true,
                textColor: .black
            ),
            margins: 24,
            pageSize: CGSize(width: 402, height: 874),
            safeArea: EdgeInsets()
        )
    }

    private func layout(html: String) async -> ChapterLayout {
        await ChapterLayout.make(
            chapterId: 1,
            content: await ChapterContent.prepare(html: html),
            heading: ChapterHeading.make(position: 1, title: nil),
            context: Self.testContext
        )
    }

    /// Nonsense built from syllables, the same every run.
    static func words(_ count: Int) -> String {
        let syllables = [ "ра", "то", "ни", "све", "ло", "ка", "мир", "сту", "бе", "гра", "де", "жи" ]
        var seed: UInt64 = 20_260_831
        let next: () -> UInt64 = {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return seed >> 33
        }

        return (0 ..< count)
            .map { _ in
                let length = Int(next() % 3) + 1
                return (0 ..< length).map { _ in syllables[Int(next()) % syllables.count] }.joined()
            }
            .joined(separator: " ")
    }
}
