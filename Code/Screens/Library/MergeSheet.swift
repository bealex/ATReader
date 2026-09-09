//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import DesignSystem
import SwiftUI

/// One thing that can be held together with another: a series, or a name a writer goes by.
struct MergeChoice: Identifiable {
    let id: String
    let title: String
    let detail: String
    let count: Int
}

/// Holding several of one thing together, when only the reader can say they are one thing.
///
/// A story written by more than one author arrives as a series apiece, and one writer reaches two
/// services under two spellings of their name. Nothing either service says puts them together, so the
/// reader picks what belongs with what and the shelf keeps it.
struct MergeSheet: View {
    let title: LocalizedStringKey
    let choices: [MergeChoice]
    let onCombine: ([String], String) -> Void

    @State
    private var picked: Set<String> = []

    @State
    private var name = ""

    @State
    private var query = ""

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("merge.name")
                } header: {
                    Text("Held under")
                }

                Section {
                    ForEach(shown) { choice in
                        Button {
                            toggle(choice)
                        } label: {
                            row(choice)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .searchable(text: $query)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            // Under the list rather than in the bar: searching takes the navigation bar away, and
            // searching is how the reader finds the second of the two things they are holding
            // together. A button that leaves at the moment it is needed is not a button.
            .safeAreaInset(edge: .bottom) {
                Button {
                    onCombine(choices.filter { picked.contains($0.id) }.map(\.id), name)
                    dismiss()
                } label: {
                    Text("Combine").actionLabel()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isReady)
                .padding(.horizontal, Design.Space.extraLarge)
                .padding(.bottom, Design.Space.medium)
                .accessibilityIdentifier("merge.combine")
            }
        }
    }

    private func row(_ choice: MergeChoice) -> some View {
        RowStack(spacing: Design.Space.medium) {
            LineGlyph(systemImage: picked.contains(choice.id) ? "checkmark.circle.fill" : "circle")
                .font(Design.Control.barGlyph)
                .foregroundStyle(picked.contains(choice.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))

            VStack(alignment: .leading, spacing: Design.Space.nudge) {
                Text(choice.title)
                    .lineLimit(1)

                if !choice.detail.isEmpty {
                    Text(choice.detail)
                        .font(Design.Style.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Design.Space.medium)

            Text(choice.count, format: .number)
                .font(Design.Style.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(picked.contains(choice.id) ? [ .isButton, .isSelected ] : .isButton)
    }

    /// Two things to hold together, and something to hold them under.
    private var isReady: Bool {
        picked.count > 1 && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// What the search leaves, with everything already picked kept in sight: a reader who searches
    /// again should not have to wonder what they had chosen before they did.
    private var shown: [MergeChoice] {
        let asked = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !asked.isEmpty else { return choices }

        return choices.filter {
            picked.contains($0.id)
                || $0.title.lowercased().contains(asked)
                || $0.detail.lowercased().contains(asked)
        }
    }

    private func toggle(_ choice: MergeChoice) {
        if picked.contains(choice.id) {
            picked.remove(choice.id)
            return
        }

        picked.insert(choice.id)

        // The first thing picked names the whole, until the reader says otherwise.
        if name.isEmpty { name = choice.title }
    }
}
