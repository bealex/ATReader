//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import Testing
import UIKit

@testable import ATReader

/// A page taken off a device, at the settings it was read at.
///
/// The text is a book's and stays out of this repository. Name a file in `TEST_RUNNER_AT_TEST_PAGE`
/// to run these, a debug report's `page.txt` being what they want; without it they pass having checked
/// nothing but the measure. `xcodebuild` strips that prefix and hands the rest to the test process, so
/// the plain name never arrives.
@MainActor
struct DevicePageTests {
    /// The reader's own settings, taken from a report's `settings.txt`.
    static var context: ChapterLayout.Context {
        var style = JustificationTests.testContext.style
        style.face = .serif
        style.weight = .regular
        style.fontSize = 21
        style.lineSpacing = 3
        style.letterSpacing = -0.5
        style.justifiesRussian = true
        style.justifiesEnglish = false

        return ChapterLayout.Context(
            style: style,
            margins: 37,
            pageSize: CGSize(width: 440, height: 956),
            safeArea: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)
        )
    }

    private func layout() async -> ChapterLayout? {
        guard
            let path = ProcessInfo.processInfo.environment["AT_TEST_PAGE"],
            let source = try? String(contentsOfFile: path, encoding: .utf8)
        else { return nil }

        let html = source
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { "<p>\($0)</p>" }
            .joined()

        return await ChapterLayout.make(
            chapterId: 1,
            content: await ChapterContent.prepare(html: html),
            heading: ChapterHeading.make(position: 1, title: nil),
            context: Self.context
        )
    }

    /// The measure the reader had, which holds whether or not the page itself is to hand.
    @Test
    func theContextMatchesTheDevice() {
        #expect(Int(Self.context.textSize.width) == 366)
        #expect(Int(Self.context.textSize.height) == 771)
    }

    @Test
    func everyShortLineHasAReason() async {
        guard let layout = await layout() else { return }

        let measure = Self.context.textSize.width
        let unexplained = layout.typesetLines
            .filter { $0.isJustified && !$0.isHeading && !$0.endsParagraph }
            .filter { $0.width < measure * 0.96 && $0.shortReason == nil }

        #expect(unexplained.isEmpty, "\(unexplained.count) line(s) short with no reason given")
    }

    @Test
    func noLineOverrunsTheMeasure() async {
        guard let layout = await layout() else { return }

        let measure = Self.context.textSize.width
        let over = layout.typesetLines.filter { $0.width > measure + Self.context.style.fontSize }

        #expect(over.isEmpty, "\(over.count) line(s) past the measure")
    }

    /// One paragraph in, one paragraph out, on a real page as much as a written one.
    @Test
    func everyParagraphEndsOnce() async {
        guard let layout = await layout() else { return }

        let endings = layout.typesetLines.filter { $0.endsParagraph && !$0.isHeading }.count

        #expect(endings > 0)
    }
}
