//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import DesignSystem
import SwiftUI

extension ReaderScreen {
    /// The bar for finding a passage, standing on the line the page number is set on.
    ///
    /// One pane: the words to look for, how many places in the book carry them, and the way through
    /// those places. What stands at its far end depends on the keyboard, since the two are never both
    /// wanted: with the keyboard up the reader is still typing and wants it out of the way, and with it
    /// down they are reading the places found and want the way to the next.
    struct SearchBar: View {
        let model: Model

        @Binding
        var query: String

        @FocusState.Binding
        var focused: Bool

        let onClose: () -> Void

        @Environment(ReaderSettings.self)
        private var settings

        var body: some View {
            GlassRow {
                TextField("Find in book", text: $query)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .onSubmit { model.find(query) }
                    .foregroundStyle(settings.theme.foreground)
                    .padding(.leading, Design.Space.extraLarge)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("reader.search.field")

                tally

                if focused, !query.isEmpty {
                    Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") {
                        model.find(query)
                        focused = false
                    }
                    .accessibilityIdentifier("reader.search.done")
                } else if !focused {
                    Button("Previous", systemImage: "chevron.up") { model.showPreviousFound() }
                        .disabled(model.found.isEmpty)
                        .accessibilityIdentifier("reader.search.previous")

                    Button("Next", systemImage: "chevron.down") { model.showNextFound() }
                        .disabled(model.found.isEmpty)
                        .accessibilityIdentifier("reader.search.next")
                }

                Button("Close", systemImage: "xmark", action: onClose)
                    .accessibilityIdentifier("reader.search.close")
            }
        }

        /// How many places carry the words, and which of them the reader is standing on.
        @ViewBuilder
        private var tally: some View {
            if model.isFinding {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Searching")
            } else if !model.findQuery.isEmpty {
                Text(verbatim: model.found.isEmpty ? "0" : "\(standing)/\(model.found.count)")
                    .font(Design.Style.caption.monospacedDigit())
                    .foregroundStyle(settings.theme.foreground.opacity(Self.ink))
                    .accessibilityLabel(
                        model.found.isEmpty
                            ? Text("Nothing found")
                            : Text("\(standing) of \(model.found.count) found")
                    )
                    .accessibilityIdentifier("reader.search.tally")
            }
        }

        /// Which place the reader stands on, counted from one as a reader counts.
        private var standing: Int { (model.foundAt ?? 0) + 1 }

        /// A shade off the text's own ink: the count is the app's, not the book's.
        private static let ink: CGFloat = 0.55
    }
}
