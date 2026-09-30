//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import SwiftUI
import Testing

@testable import Bookhold

/// A table opened whole grows each row to the deepest of its wrapped cells. The table is nonsense.
@MainActor
struct TableSheetTests {
    private static let long = String(repeating: "Alpha bravo charlie delta echo foxtrot. ", count: 4)

    private func height(of table: BookTable) throws -> CGFloat {
        let defaults = try #require(UserDefaults(suiteName: "TableSheetTests"))
        let settings = ReaderSettings(defaults: defaults)
        let renderer = ImageRenderer(content: ReaderScreen.TableGrid(table: table).environment(settings))

        renderer.scale = 2

        if let image = renderer.uiImage, let png = image.pngData() {
            try? png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("table-sheet.png"))
        }

        return try #require(renderer.uiImage).size.height
    }

    @Test
    func growsARowToItsWrappedCell() throws {
        let short = BookTable(rows: [ [ .init(text: "Golf"), .init(text: "Hotel") ] ])
        let wrapped = BookTable(rows: [ [ .init(text: "Golf"), .init(text: Self.long) ] ])

        let one = try height(of: short)
        let several = try height(of: wrapped)

        // Four sentences in a column held to sixteen ems run to several lines.
        #expect(several > one * 2)
    }
}
