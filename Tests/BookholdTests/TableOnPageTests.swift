//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Testing
import UIKit

@testable import Bookhold
@testable import BookRenderer

/// A table is drawn on the page as a picture shrunk to the measure, and a tap on it finds the table.
/// The tables here are generated nonsense.
@MainActor
struct TableOnPageTests {
    private static let wide = """
        <p>Alpha bravo charlie.</p>
        <table>
          <tr><th>Delta</th><th>Echo</th><th>Foxtrot</th><th>Golf</th><th>Hotel</th><th>India</th></tr>
          <tr><td>Juliet kilo lima</td><td>Mike</td><td>November oscar</td><td>Papa</td><td>Quebec romeo</td><td>Sierra</td></tr>
        </table>
        <p>Tango uniform.</p>
        """

    private func layout(_ html: String) async -> ChapterLayout {
        await ChapterLayout.make(
            chapterId: 1,
            content: await ChapterContent.prepare(html: html),
            heading: ChapterHeading(),
            context: JustificationTests.testContext
        )
    }

    /// Wider than the column, so it is shrunk to the measure rather than running off it.
    @Test
    func shrinksAWideTableToTheMeasure() async throws {
        let layout = await layout(Self.wide)
        let pictures = layout.typesetLines.filter(\.isImage)

        #expect(pictures.count == 1)
        #expect(abs((pictures.first?.width ?? 0) - JustificationTests.testContext.textSize.width) < 1)
    }

    /// Narrower than the column, so it stays the size of the page's own type.
    @Test
    func leavesANarrowTableAtItsOwnSize() async throws {
        let layout = await layout("<table><tr><td>Alpha</td></tr></table>")
        let picture = try #require(layout.typesetLines.first { $0.isImage })

        // The width is counted from the column's edge, and the picture stands centred in it.
        #expect(picture.width - picture.origin < JustificationTests.testContext.textSize.width / 2)
    }

    @Test
    func findsTheTableUnderAFinger() async throws {
        let layout = await layout(Self.wide)
        let page = try #require(layout.pages.first)
        let context = JustificationTests.testContext
        let lines = layout.typesetLines(on: page)
        let index = try #require(lines.firstIndex { $0.isImage })
        let top = context.textRect.minY + page.top + lines[..<index].reduce(0) { $0 + $1.height + page.leading }
        let over = CGPoint(x: context.textRect.midX, y: top + page.imagePadding + lines[index].height / 2)
        let above = CGPoint(x: context.textRect.midX, y: context.textRect.minY + page.top + 1)

        #expect(layout.table(at: over, on: page)?.rows.first?.first?.text == "Delta")
        #expect(layout.table(at: above, on: page) == nil)
        #expect(layout.tables(on: page).count == 1)
    }

    /// Drawn text is invisible to VoiceOver, so the page reads the table out instead.
    @Test
    func readsTheTableOutForVoiceOver() async throws {
        let layout = await layout(Self.wide)
        let page = try #require(layout.pages.first)
        let text = layout.pageText(page)

        #expect(text.contains("Delta, Echo, Foxtrot"))
        #expect(!text.contains(String(ChapterPagination.pictureMark)))
    }

    /// Imported whole, the Markdown file's table reaches the page as the same picture.
    @Test
    func readsAMarkdownTableOntoThePage() async throws {
        let book = try await BookImporting.read(Data("# Alpha\n\n| Bravo | Charlie |\n|---|---|\n| 1 | 2 |\n".utf8)).book
        let section = try #require(book.sections.first)
        let layout = await layout(section.html)

        #expect(layout.typesetLines.contains { $0.isImage })
    }
}
