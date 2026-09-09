//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import DesignSystem
import SwiftUI

/// What a series is made of, and the one place its order can be changed.
///
/// The shelf shows a series as artwork, which says nothing about which volume is which or how much of
/// it is behind the reader. This says both, and is where a series is put in order.
enum SeriesScreen {
    struct Component: View {
        let series: String

        @State
        private var model: Model?

        @State
        private var isConfirmingUngroup = false

        @Environment(\.dismiss)
        private var dismiss

        var body: some View {
            List {
                if let model {
                    about(model)
                    books(model)
                }
            }
            .navigationTitle(series)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { EditButton() }
            .onAppear {
                if model == nil { model = Model(series: series) }
            }
            .task { await model?.load() }
            .confirmationDialog(
                "Break up this series?",
                isPresented: $isConfirmingUngroup,
                titleVisibility: .visible,
                actions: {
                    Button("Yes, break it up", role: .destructive) {
                        Task {
                            await model?.ungroup()
                            dismiss()
                        }
                    }
                    Button("Cancel", role: .cancel, action: {})
                },
                message: {
                    Text("The books go back to whatever the service and their own files say they belong to.")
                }
            )
        }

        @ViewBuilder
        private func about(_ model: Model) -> some View {
            Section {
                if let author = model.author {
                    LabeledContent {
                        Text(author)
                    } label: {
                        Label("Author", systemImage: "person")
                    }
                }

                LabeledContent {
                    Text("\(model.readCount) of \(model.books.count)")
                } label: {
                    Label("Read", systemImage: "checkmark.circle")
                }

                if let missing = model.numbering?.missing, !missing.isEmpty {
                    LabeledContent {
                        Text(missing.map(String.init).formatted(.list(type: .and)))
                    } label: {
                        Label("Volumes you don't have", systemImage: "questionmark.square.dashed")
                    }
                }

                // Only a series the reader made can be broken up; the service's own has nothing to undo.
                if model.isArranged {
                    Button(role: .destructive) {
                        isConfirmingUngroup = true
                    } label: {
                        Label("Break up this series", systemImage: "rectangle.split.3x1")
                    }
                    .accessibilityIdentifier("series.ungroup")
                }
            }
        }

        private func books(_ model: Model) -> some View {
            Section {
                ForEach(model.books) { work in
                    NavigationLink(value: AppRoute.work(id: work.id, title: work.title)) {
                        RowStack(spacing: Design.Space.medium) {
                            LineGlyph(systemImage: "checkmark.circle.fill")
                                .font(Design.Style.caption)
                                .foregroundStyle(.tint)
                                .opacity(work.isFinishedReading ? 1 : 0)

                            if let number = model.number(of: work) { SeriesNumber(number: number) }

                            Text(model.title(of: work))
                                .lineLimit(2)
                        }
                    }
                }
                .onMove { picked, destination in
                    Task { await model.move(from: picked, to: destination) }
                }
            } header: {
                Text("Books")
            } footer: {
                Text("Drag to put the series in the order you read it.")
            }
        }
    }
}
