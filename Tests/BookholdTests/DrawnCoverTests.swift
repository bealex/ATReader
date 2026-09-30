//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import Testing
import UIKit

@testable import Bookhold

/// A book with no cover of its own gets one drawn, the same one every time. The titles are nonsense.
@MainActor
struct DrawnCoverTests {
    @Test
    func drawsABookShapedCover() throws {
        let data = try #require(DrawnCover.draw(title: "Alpha bravo", format: "md", seed: "md:name:Alpha bravo|"))
        let image = try #require(UIImage(data: data))

        try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("drawn-cover.jpg"))

        #expect(abs(image.size.height / image.size.width - 1.5) < 0.01)
    }

    @Test
    func keepsItsColoursForTheSameBookAndChangesThemForAnother() {
        #expect(DrawnCover.hues(for: "md:name:Alpha|") == DrawnCover.hues(for: "md:name:Alpha|"))
        #expect(DrawnCover.hues(for: "md:name:Alpha|") != DrawnCover.hues(for: "md:name:Bravo|"))
    }

    /// Read in through the importer, a Markdown file comes with a cover of its own.
    @Test
    func coversAMarkdownBookThatBroughtNone() async throws {
        let read = try await BookImporting.read(Data("# Charlie\n\nDelta echo.".utf8))

        #expect(read.book.cover != nil)
        #expect(read.book.title == "Charlie")
    }
}
