//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import DesignSystem
import SwiftUI

extension ReaderScreen {
    /// A table the page shows in miniature, set out whole in the page's own type and colours.
    ///
    /// It turns with the device even where the reader locked the page upright, since a wide table wants
    /// the room. Closing puts the lock back and waits for the screen to stand up again first, so the page
    /// underneath is never set sideways.
    struct TableSheet: View {
        let table: BookTable

        @Environment(ReaderSettings.self)
        private var settings

        @Environment(\.dismiss)
        private var dismiss

        @State
        private var isWide = false

        @State
        private var isClosing = false

        var body: some View {
            NavigationStack {
                ScrollView([ .horizontal, .vertical ]) {
                    TableGrid(table: table)
                        .padding(Design.Space.large)
                }
                .background(settings.theme.background)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { close() }
                    }
                }
            }
            .onGeometryChange(for: Bool.self) {
                $0.size.width > $0.size.height
            } action: { wide in
                isWide = wide
                if isClosing, !wide { dismiss() }
            }
            .onAppear { OrientationLock.release() }
            .onDisappear { OrientationLock.hold() }
            .task(id: isClosing) {
                guard isClosing else { return }

                // Whatever the screen does, the table doesn't outstay the tap that closed it.
                do { try await Task.sleep(for: Self.turnAllowance) } catch { return }

                dismiss()
            }
            .accessibilityIdentifier("reader.table")
        }

        private func close() {
            OrientationLock.hold()

            guard isWide, OrientationLock.mask == .portrait else { return dismiss() }

            isClosing = true
        }

        /// Longer than the screen takes to stand upright.
        private static let turnAllowance = Duration.seconds(1)
    }

    /// The table's cells, a hairline apart over the rule colour, which draws every rule at once.
    ///
    /// Every column is given the width the page's picture gives it. A width left to the grid is asked
    /// for before the words wrap, and a row sized that way is one line deep whatever its cells hold.
    struct TableGrid: View {
        let table: BookTable

        @Environment(ReaderSettings.self)
        private var settings

        var body: some View {
            let widths = table.columnWidths(font: settings.textStyle.font).map { $0 + Self.slack }

            return Grid(
                alignment: .topLeading,
                horizontalSpacing: Design.Stroke.hairline,
                verticalSpacing: Design.Stroke.hairline
            ) {
                ForEach(table.rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(0 ..< table.columnCount, id: \.self) { column in
                            cell(row: row, column: column, width: widths[column])
                        }
                    }
                }
            }
            .padding(Design.Stroke.hairline)
            .background(settings.theme.foreground.opacity(Self.ruleShade))
            .textSelection(.enabled)
        }

        private func cell(row: Int, column: Int, width: CGFloat) -> some View {
            let cells = table.rows[row]
            let isHeader = table.isHeader(row: row)
            let alignment = table.alignment(ofColumn: column)

            return Text(column < cells.count ? Self.text(cells[column]) : AttributedString())
                .font(Font(settings.textStyle.font))
                .bold(isHeader)
                .foregroundStyle(settings.theme.foreground)
                .multilineTextAlignment(alignment.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width, alignment: alignment.frame)
                .padding(.horizontal, settings.textStyle.fontSize * Self.cellInset)
                .padding(.vertical, settings.textStyle.fontSize * Self.cellInset / 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment.frame)
                .background(isHeader ? settings.theme.foreground.opacity(Self.headerShade) : .clear)
                .background(settings.theme.background)
        }

        /// A cell's words with the book's own emphasis on them.
        private static func text(_ cell: BookTable.Cell) -> AttributedString {
            let text = NSMutableAttributedString(string: cell.text)

            for style in cell.styles {
                let range = NSRange(location: style.location, length: style.length)

                guard range.length > 0, NSMaxRange(range) <= text.length else { continue }

                let intent: InlinePresentationIntent = style.emphasis == .bold ? .stronglyEmphasized : .emphasized
                let held = text.attribute(.inlinePresentationIntent, at: range.location, effectiveRange: nil) as? UInt

                text.addAttribute(
                    .inlinePresentationIntent,
                    value: intent.union(InlinePresentationIntent(rawValue: held ?? 0)).rawValue,
                    range: range
                )
            }

            return (try? AttributedString(text, including: \.foundation)) ?? AttributedString(cell.text)
        }

        /// Room for SwiftUI measuring a line a fraction wider than the page does, which would wrap it.
        private static let slack: CGFloat = 2
        /// The same proportions the page's miniature is drawn in, against the size of the type.
        private static let cellInset: CGFloat = 0.6
        private static let headerShade = 0.08
        private static let ruleShade = 0.4
    }
}

private extension BookTable.Alignment {
    var text: TextAlignment {
        switch self {
            case .leading: .leading
            case .center: .center
            case .trailing: .trailing
        }
    }

    /// Top first, as the page's picture sets a short cell beside a deep one.
    var frame: Alignment {
        switch self {
            case .leading: .topLeading
            case .center: .top
            case .trailing: .topTrailing
        }
    }
}
