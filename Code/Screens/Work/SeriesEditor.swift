//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import DesignSystem
import SwiftUI

/// The series and volume as the editor holds them: each one either the book's own or the reader's, and
/// the reader's either a value or nothing at all.
struct SeriesChoice: Equatable {
    var name = ""
    /// True while the series is taken from the book itself.
    var namesOwn = true
    var number = ""
    /// True while the volume is taken from the book itself.
    var numbersOwn = true

    init(_ edit: SQLiteBookStore.SeriesEdit? = nil) {
        if let series = edit?.series {
            name = series
            namesOwn = false
        }

        if let volume = edit?.volume {
            number = volume > 0 ? String(volume) : ""
            numbersOwn = false
        }
    }

    /// What to store: `nil` where both are the book's own.
    var edit: SQLiteBookStore.SeriesEdit? {
        guard !namesOwn || !numbersOwn else { return nil }

        return SQLiteBookStore.SeriesEdit(
            series: namesOwn ? nil : name.trimmingCharacters(in: .whitespacesAndNewlines),
            volume: numbersOwn ? nil : Int(number.trimmingCharacters(in: .whitespaces)) ?? 0
        )
    }
}

/// One field that is either the book's own value, shown greyed, or the reader's, which may be empty.
private struct OverrideField: View {
    let title: LocalizedStringKey
    @Binding
    var text: String
    @Binding
    var isOwn: Bool
    /// What the field says while it takes the book's own value.
    let own: Text
    /// What it says while the reader has left it empty.
    let none: Text
    var keyboard: UIKeyboardType = .default

    var body: some View {
        LabeledContent {
            HStack(spacing: Design.Space.medium) {
                TextField(title, text: $text, prompt: isOwn ? own : none)
                    .keyboardType(keyboard)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: text) { _, typed in
                        if !typed.isEmpty { isOwn = false }
                    }

                if isOwn {
                    Button {
                        isOwn = false
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .accessibilityLabel("No value")
                } else {
                    Button {
                        text = ""
                        isOwn = true
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                    .accessibilityLabel("Take from the book")
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        } label: {
            Text(title)
        }
    }
}

/// The two fields, set against what the book states itself.
private struct SeriesFields {
    @Binding
    var choice: SeriesChoice
    let draft: SeriesCorrection.Draft

    var name: some View {
        OverrideField(
            title: "Series name",
            text: $choice.name,
            isOwn: $choice.namesOwn,
            own: draft.ownSeries.map { Text("From the book: \($0)") } ?? Text("From the book: no series"),
            none: Text("No series")
        )
        .accessibilityIdentifier("series.name")
    }

    var volume: some View {
        OverrideField(
            title: "Volume",
            text: $choice.number,
            isOwn: $choice.numbersOwn,
            own: draft.ownVolume.map { Text("From the book: \($0)") } ?? Text("From the book: no volume"),
            none: Text("No volume"),
            keyboard: .numberPad
        )
        .accessibilityIdentifier("series.volume")
    }
}

private struct SeriesFootnote: View {
    var body: some View {
        Text("An empty field means none. The arrow takes a field from the book again.")
    }
}

/// Where the reader corrects which series a book is in, and which volume of it, away from its page.
struct SeriesEditor: View {
    let work: Book
    /// The series this book's writer has in the library, offered to pick rather than type.
    let writersSeries: [String]
    let onSave: (SQLiteBookStore.SeriesEdit?) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State
    private var draft: SeriesCorrection.Draft?

    @State
    private var choice = SeriesChoice()

    var body: some View {
        NavigationStack {
            List {
                Group {
                    heading

                    if let draft {
                        let fields = SeriesFields(choice: $choice, draft: draft)

                        Section {
                            fields.name
                            fields.volume
                        } footer: {
                            SeriesFootnote()
                        }

                        if !writersSeries.isEmpty {
                            Section("This writer’s series") {
                                ForEach(writersSeries, id: \.self) { series in
                                    Button {
                                        choice.name = series
                                        choice.namesOwn = false
                                    } label: {
                                        Text(verbatim: series)
                                    }
                                }
                            }
                        }

                        Section {
                            Button("Use what the book says") { choice = SeriesChoice() }
                                .disabled(choice == SeriesChoice())
                                .accessibilityIdentifier("series.restore")
                        }
                    }
                }
                .listRowBackground(Design.Surface.card)
            }
            .listOnScreen()
            .navigationTitle("Series and volume")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if choice != SeriesChoice(draft?.edit) { onSave(choice.edit) }

                        dismiss()
                    }
                    .disabled(draft == nil)
                    .accessibilityIdentifier("series.save")
                }
            }
            .task {
                let loaded = await SeriesCorrection.draft(for: work.id)

                draft = loaded
                choice = SeriesChoice(loaded.edit)
            }
        }
    }

    /// Which book this is, since the sheet covers the shelf it was opened from.
    private var heading: some View {
        HStack(spacing: Design.Space.large) {
            CoverImage(url: work.coverURL, width: Design.Size.rowCover)

            VStack(alignment: .leading, spacing: Design.Space.extraSmall) {
                Text(verbatim: work.title)
                    .font(Design.Style.item)

                Text(verbatim: work.authorLine)
                    .font(Design.Style.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The same fields on the book's own page, saved with a button that shows once something changed.
struct SeriesInlineEditor: View {
    let draft: SeriesCorrection.Draft
    let writersSeries: [String]
    let onSave: (SQLiteBookStore.SeriesEdit?) -> Void

    @State
    private var choice = SeriesChoice()

    private var saved: SeriesChoice { SeriesChoice(draft.edit) }

    var body: some View {
        let fields = SeriesFields(choice: $choice, draft: draft)

        VStack(alignment: .leading, spacing: Design.Space.medium) {
            fields.name

            Divider()

            fields.volume

            Divider()

            HStack(spacing: Design.Space.medium) {
                if !writersSeries.isEmpty {
                    Menu {
                        ForEach(writersSeries, id: \.self) { series in
                            Button {
                                choice.name = series
                                choice.namesOwn = false
                            } label: {
                                Text(verbatim: series)
                            }
                        }
                    } label: {
                        Label("This writer’s series", systemImage: "list.bullet")
                    }
                }

                Spacer()

                if choice != saved {
                    Button("Cancel") { choice = saved }
                        .buttonStyle(.bordered)

                    Button("Save") { onSave(choice.edit) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("series.save")
                }
            }
            .controlSize(.small)

            SeriesFootnote()
                .font(Design.Style.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { choice = saved }
        .onChange(of: draft) { _, _ in choice = saved }
    }
}
