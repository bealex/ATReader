//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// A table the book sets out: rows of cells, the first few of them heading the rest.
///
/// A chapter body writes one as `<table>` markup, with `<th>` for a heading cell and
/// `style="text-align:right"` (or `center`) on a cell for how its column is aligned.
public struct BookTable: Codable, Sendable, Hashable {
    public enum Alignment: String, Codable, Sendable {
        case leading
        case center
        case trailing
    }

    /// One cell's words, with the stretches of them the book set apart.
    public struct Cell: Codable, Sendable, Hashable {
        public let text: String
        public let styles: [StyleMark]

        public init(text: String, styles: [StyleMark] = []) {
            self.text = text
            self.styles = styles
        }
    }

    /// Every row in reading order. Rows may be shorter than the widest one.
    public let rows: [[Cell]]
    /// How many of the opening rows head the table.
    public let headerRows: Int
    /// How each column is aligned, by column. A column past the end is aligned to the leading edge.
    public let alignments: [Alignment]

    public init(rows: [[Cell]], headerRows: Int = 0, alignments: [Alignment] = []) {
        self.rows = rows
        self.headerRows = min(headerRows, rows.count)
        self.alignments = alignments
    }

    public var columnCount: Int { rows.map(\.count).max() ?? 0 }

    public func alignment(ofColumn column: Int) -> Alignment {
        column < alignments.count ? alignments[column] : .leading
    }

    public func isHeader(row: Int) -> Bool { row < headerRows }

    /// The table read out row by row, for VoiceOver.
    public var spokenText: String {
        rows.map { $0.map(\.text).joined(separator: ", ") }.joined(separator: ". ")
    }
}
