//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Testing
import UIKit

@testable import ATReader

/// How far apart a justified line may set its words.
///
/// Reaching the measure is not enough on its own. Gaps several times the width the font gives a space
/// read as holes down the page, and the breaker is meant to have found something better first: a word
/// drawn up from the line below, or a word broken.
@MainActor
struct SpacingTests {
    /// The widest a gap may stand, against the font's own space.
    ///
    /// The levers take a line to two and a half times a space between them, and half a space past that
    /// is as far as the breaker should ever have to reach. A line of two long words has the one gap to
    /// fill itself from and no rearranging can save it, so that one is held only to what a two-word
    /// line can look like.
    static let widest: CGFloat = 3.2
    static let widestOnOneGap: CGFloat = 5

    @Test(arguments: renderingSettings)
    func theCorpusKeepsItsGapsClosed(setting: Setting) async {
        await check(context: context(setting), html: RenderingTests.html, what: "the corpus at \(setting)")
    }

    /// Running prose, where a paragraph is long enough for the breaker to have a choice.
    @Test(arguments: renderingSettings)
    func runningProseKeepsItsGapsClosed(setting: Setting) async {
        let html = JustificationTests.prose(6)
            .components(separatedBy: "\n")
            .map { "<p>\($0)</p>" }
            .joined()

        await check(context: context(setting), html: html, what: "running prose at \(setting)")
    }

    /// Every page reported off a device, at the settings it was read at.
    @Test
    func everyReportedPageKeepsItsGapsClosed() async {
        for report in PageReport.all {
            await check(layout: await report.layout(), what: "\(report)")
        }
    }

    // MARK: - Checking one setting

    private func context(_ setting: Setting) -> ChapterLayout.Context {
        var context = JustificationTests.testContext
        context.style.face = setting.face
        context.style.fontSize = setting.size
        context.margins = setting.margins
        return context
    }

    private func check(context: ChapterLayout.Context, html: String, what: String) async {
        let layout = await ChapterLayout.make(
            chapterId: 1,
            content: await ChapterContent.prepare(html: html),
            heading: ChapterHeading.make(position: 1, title: nil),
            context: context
        )

        await check(layout: layout, what: what)
    }

    private func check(layout: ChapterLayout, what: String) async {
        let loosest = layout.typesetLines
            .filter { $0.isJustified && !$0.isHeading && !$0.endsParagraph }
            .sorted { $0.gapMultiple > $1.gapMultiple }
        let open = loosest.filter { $0.gapMultiple > ($0.gaps > 1 ? Self.widest : Self.widestOnOneGap) }

        survey(loosest, what: what)

        let worst = open.prefix(5)
            .map { String(format: "%.2f× over %d gap(s): %@", $0.gapMultiple, $0.gaps, $0.text.trimmed) }
            .joined(separator: "\n  ")

        #expect(open.isEmpty, "\(open.count) line(s) pulled apart in \(what):\n  \(worst)")
    }

    /// The loosest lines of one column, written out where a directory was named.
    ///
    /// What the numbers in `ColumnComposer.Rules` are tuned against: run this before a change to them
    /// and after it, and the two files say what moved.
    private func survey(_ loosest: [ChapterLayout.TypesetLine], what: String) {
        guard let directory = PageRenderTests.directory else { return }

        let lines = loosest.prefix(3)
            .map { String(format: "  %.2f× over %d gap(s): %@", $0.gapMultiple, $0.gaps, $0.text.trimmed) }
            .joined(separator: "\n")
        let row = String(format: "%.2f×  %@\n%@\n", loosest.first?.gapMultiple ?? 1, what, lines)

        let folder = URL(fileURLWithPath: directory)
        let file = folder.appendingPathComponent("spacing.txt")

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        guard let handle = try? FileHandle(forWritingTo: file) else {
            try? row.write(to: file, atomically: true, encoding: .utf8)
            return
        }

        handle.seekToEndOfFile()
        handle.write(Data(row.utf8))
        try? handle.close()
    }
}
