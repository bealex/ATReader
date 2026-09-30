//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import UIKit

public extension NSAttributedString.Key {
    /// The table a block sets out, on the character standing for its picture.
    static let bookTable = NSAttributedString.Key("ATBookTable")
}

/// A table drawn as a picture in black on nothing, which the page then sets like any monochrome plate:
/// in its own two colours, shrunk to the measure, and never blown up past its own size.
enum TablePicture {
    /// What the picture of a table is kept under: the table, and everything about the type it is drawn in.
    static func key(_ table: BookTable, style: ChapterTextStyle) -> String {
        "table:\(table.hashValue):\(style.face.rawValue):\(style.weight.rawValue):\(style.fontSize)"
    }

    /// A drawing for every table among the paragraphs, by the key its picture is kept under.
    static func drawings(
        for paragraphs: [Paragraph],
        style: ChapterTextStyle
    ) -> [String: @Sendable () -> DrawnPicture?] {
        let font = style.font

        return paragraphs.reduce(into: [:]) { result, paragraph in
            guard let table = paragraph.table else { return }

            result[key(table, style: style)] = { draw(table, font: font) }
        }
    }

    /// The table at the size of the page's own type, drawn at more than one pixel to the point so a
    /// picture shrunk to the measure stays sharp.
    static func draw(_ table: BookTable, font: UIFont) -> DrawnPicture? {
        let grid = Grid(table, font: font)

        guard grid.size.width > 0, grid.size.height > 0 else { return nil }

        let scale = min(drawnScale, largestSide / max(grid.size.width, grid.size.height))
        let format = UIGraphicsImageRendererFormat()

        format.scale = scale
        format.opaque = false

        let image = UIGraphicsImageRenderer(size: grid.size, format: format).image { context in
            grid.draw(in: context.cgContext, pixel: 1 / scale)
        }

        return image.cgImage.map { DrawnPicture(image: $0, scale: scale) }
    }

    private static let drawnScale: CGFloat = 2
    /// The most pixels a side is drawn at, which a very large table gives up sharpness to stay under.
    private static let largestSide: CGFloat = 4096

    /// Every cell measured and placed.
    private struct Grid {
        let cells: [[NSAttributedString]]
        let columns: [CGFloat]
        let rows: [CGFloat]
        let headerRows: Int
        let padding: CGSize

        init(_ table: BookTable, font: UIFont) {
            let typeSize = font.pointSize
            let bold = ChapterPagination.adding(.bold, to: font)

            padding = CGSize(width: typeSize * TablePicture.cellInset, height: typeSize * TablePicture.cellInset / 2)
            headerRows = table.headerRows
            cells = table.rows.enumerated().map { row, cells in
                cells.enumerated().map { column, cell in
                    TablePicture.text(
                        cell,
                        font: table.isHeader(row: row) ? bold : font,
                        alignment: table.alignment(ofColumn: column)
                    )
                }
            }

            let columns = TablePicture.columns(of: cells, count: table.columnCount, typeSize: typeSize)
            let wrapped = columns

            self.columns = columns
            rows = cells.map { row in
                row.enumerated().reduce(font.lineHeight) { deepest, each in
                    let height = each.element.boundingRect(
                        with: CGSize(width: wrapped[each.offset], height: .greatestFiniteMagnitude),
                        options: [ .usesLineFragmentOrigin ],
                        context: nil
                    ).height

                    return max(deepest, height.rounded(.up))
                }
            }
        }

        var size: CGSize {
            CGSize(
                width: columns.reduce(0) { $0 + $1 + padding.width * 2 },
                height: rows.reduce(0) { $0 + $1 + padding.height * 2 }
            )
        }

        func draw(in context: CGContext, pixel: CGFloat) {
            let bounds = CGRect(origin: .zero, size: size)
            let headerDepth = rows.prefix(headerRows).reduce(0) { $0 + $1 + padding.height * 2 }

            UIColor.black.withAlphaComponent(TablePicture.headerShade).setFill()
            context.fill(CGRect(x: 0, y: 0, width: bounds.width, height: headerDepth))

            var top: CGFloat = 0

            for (row, cells) in cells.enumerated() {
                var left: CGFloat = 0

                for (column, width) in columns.enumerated() {
                    if column < cells.count {
                        cells[column].draw(
                            with: CGRect(
                                x: left + padding.width,
                                y: top + padding.height,
                                width: width,
                                height: rows[row]
                            ),
                            options: [ .usesLineFragmentOrigin ],
                            context: nil
                        )
                    }

                    left += width + padding.width * 2
                }

                top += rows[row] + padding.height * 2
            }

            rules(in: context, bounds: bounds, pixel: pixel)
        }

        /// A hairline round every cell, one pixel wide at the size the table is drawn.
        private func rules(in context: CGContext, bounds: CGRect, pixel: CGFloat) {
            let path = CGMutablePath()
            let inset = bounds.insetBy(dx: pixel / 2, dy: pixel / 2)
            var top: CGFloat = 0

            path.addRect(inset)

            for row in rows.dropLast() {
                top += row + padding.height * 2
                path.move(to: CGPoint(x: inset.minX, y: top))
                path.addLine(to: CGPoint(x: inset.maxX, y: top))
            }

            var left: CGFloat = 0

            for column in columns.dropLast() {
                left += column + padding.width * 2
                path.move(to: CGPoint(x: left, y: inset.minY))
                path.addLine(to: CGPoint(x: left, y: inset.maxY))
            }

            context.setStrokeColor(UIColor.black.withAlphaComponent(TablePicture.ruleShade).cgColor)
            context.setLineWidth(pixel)
            context.addPath(path)
            context.strokePath()
        }
    }

    /// How wide each column's words run: its widest cell on one line, up to a limit past which it wraps.
    static func columns(of cells: [[NSAttributedString]], count: Int, typeSize: CGFloat) -> [CGFloat] {
        var columns = [CGFloat](repeating: typeSize, count: count)

        for row in cells {
            for (column, text) in row.enumerated() {
                let natural = text.boundingRect(
                    with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
                    options: [ .usesLineFragmentOrigin ],
                    context: nil
                ).width

                columns[column] = max(columns[column], min(typeSize * widestColumn, natural.rounded(.up)))
            }
        }

        return columns
    }

    /// One cell's words, set in the page's face with the book's own emphasis.
    static func text(_ cell: BookTable.Cell, font: UIFont, alignment: BookTable.Alignment) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()

        paragraph.alignment =
            switch alignment {
                case .leading: .natural
                case .center: .center
                case .trailing: .right
            }

        let text = NSMutableAttributedString(
            string: cell.text,
            attributes: [ .font: font, .foregroundColor: UIColor.black, .paragraphStyle: paragraph ]
        )

        for style in cell.styles {
            let range = NSRange(location: style.location, length: style.length)

            guard range.length > 0, NSMaxRange(range) <= text.length else { continue }

            text.addAttribute(.font, value: ChapterPagination.adding(style.emphasis, to: font), range: range)
        }

        return text
    }

    /// How wide a column may grow before its words wrap, in the type's own size.
    private static let widestColumn: CGFloat = 16
    /// How far a cell's words stand in from its sides, in the type's own size, and half that from its top.
    private static let cellInset: CGFloat = 0.6
    private static let headerShade: CGFloat = 0.08
    private static let ruleShade: CGFloat = 0.4
}

public extension BookTable {
    /// How wide each column's words run when set in `font`, headings in its bold, so a table shown
    /// anywhere else wraps its cells where the page's picture of it does.
    func columnWidths(font: UIFont) -> [CGFloat] {
        let bold = ChapterPagination.adding(.bold, to: font)
        let cells = rows.enumerated().map { row, cells in
            cells.map { TablePicture.text($0, font: isHeader(row: row) ? bold : font, alignment: .leading) }
        }

        return TablePicture.columns(of: cells, count: columnCount, typeSize: font.pointSize)
    }
}
