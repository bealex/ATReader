//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookRenderer
import Foundation
import Testing

@testable import Bookhold

/// A page reported with room for four more lines at its foot, cut again from the chapter it came from.
///
/// Reads `Fixtures/Reports/short-page`, which carries the whole chapter, and passes having read nothing
/// where the report isn't there. Says nothing about the text either way.
@MainActor
struct ShortPageTests {
    @Test
    func theReportedPageFillsItsMeasure() async throws {
        guard
            let root = ProcessInfo.processInfo.environment["AT_REPORTS"],
            case let folder = URL(fileURLWithPath: root).appendingPathComponent("short-page"),
            let html = try? String(contentsOf: folder.appendingPathComponent("chapter.html"), encoding: .utf8),
            let dump = try? String(contentsOf: folder.appendingPathComponent("lines.txt"), encoding: .utf8),
            let context = PageReport.setting(ofReportAt: folder)
        else { return }

        let content = await ChapterContent.prepare(html: html)
        let book = BookLayout(
            chapters: [ BookLayout.Chapter(id: 1, heading: ChapterHeading.make(position: 1, title: nil), opensItsOwnPage: true) ],
            context: context,
            content: { _ in content }
        )
        let chapter = try #require(await book.layout(of: 1))
        let opening = try #require(Self.opening(of: dump))
        let found = (chapter.sourceText as NSString).range(of: opening)

        try #require(found.location != NSNotFound, "the report's first line isn't in its own chapter")

        let page = try #require(await book.page(at: BookPosition(chapterId: 1, offset: found.location)))

        #expect(book.shortfall(of: page) < 1, "the page stands \(book.shortfall(of: page)) lines short")
    }

    /// The first two words of the page as the report dumped it, with the typesetter's marks taken out.
    private static func opening(of dump: String) -> String? {
        guard let first = dump.components(separatedBy: "\n").first?.components(separatedBy: "\t").last else { return nil }

        let words =
            first
            .replacingOccurrences(of: "\u{00AD}", with: "")
            .replacingOccurrences(of: "\u{2060}", with: "")
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        return words.isEmpty ? nil : words.prefix(2).joined(separator: " ")
    }
}
