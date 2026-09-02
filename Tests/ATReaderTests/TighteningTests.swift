//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import Testing
import UIKit

@testable import ATReader

/// A paragraph a fraction wider than the measure is closed up to fit, rather than broken with a hyphen
/// that strands the tail of a word on a line of its own.
@MainActor
struct TighteningTests {
    static let context = JustificationTests.testContext

    private func layout(_ text: String) async -> ChapterLayout {
        await ChapterLayout.make(
            chapterId: 1,
            content: await ChapterContent.prepare(html: "<p>\(text)</p>"),
            heading: ChapterHeading.make(position: 1, title: nil),
            context: Self.context
        )
    }

    private static func width(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [
            .font: context.style.font,
            .kern: context.style.letterSpacing,
        ]).width
    }

    /// A phrase whose set width lands just past the measure, within what tightening may close up.
    static func phrase(overshoot: ClosedRange<Double>) -> String? {
        // What the opening line of a paragraph holds, its indent taken off.
        let measure = context.textSize.width - context.style.font.pointSize
        var text = ""

        for word in JustificationTests.words(60).split(separator: " ") {
            text += text.isEmpty ? String(word) : " \(word)"

            var candidate = text
            while width(candidate) > measure * overshoot.upperBound, candidate.count > 1 {
                candidate.removeLast()
            }
            let ratio = width(candidate) / measure
            if overshoot.contains(ratio) { return candidate }
        }

        return nil
    }

    @Test
    func aParagraphAFractionTooWideIsSetOnOneLine() async {
        guard let text = Self.phrase(overshoot: 1.001 ... 1.015) else {
            Issue.record("no phrase landed just over the measure")
            return
        }

        let body = await layout(text).typesetLines.filter { !$0.isHeading }

        #expect(body.count == 1, "set on \(body.count) lines rather than closed up to one")
    }

    /// The limit holds: a paragraph well past the measure is still broken.
    @Test
    func aParagraphWellPastTheMeasureIsStillBroken() async {
        guard let text = Self.phrase(overshoot: 1.20 ... 1.40) else {
            Issue.record("no phrase landed well past the measure")
            return
        }

        let body = await layout(text).typesetLines.filter { !$0.isHeading }

        #expect(body.count > 1, "a paragraph well past the measure was squeezed onto one line")
    }
}
