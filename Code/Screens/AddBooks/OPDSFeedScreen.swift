//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import DesignSystem
import OPDS
import SwiftUI

/// One feed of a catalogue: the sections it leads to, or the books it ends in.
///
/// A catalogue is a tree and every level of it looks the same, so one screen draws all of them and
/// pushes another of itself for each section.
enum OPDSFeedScreen {
    struct Component: View {
        let address: String
        let url: URL
        let title: String

        @Environment(BookInbox.self)
        private var inbox

        @State
        private var model = FeedModel()

        var body: some View {
            List {
                Rows(model: model, address: address)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if model.isLoading, model.entries.isEmpty { ProgressView().controlSize(.large) }
            }
            .task {
                model.inbox = inbox
                await model.open(url, at: address)
            }
        }
    }

    /// What a feed's entries look like, wherever they are being shown from.
    struct Rows: View {
        let model: FeedModel
        let address: String

        var body: some View {
            if let message = model.message {
                Section { Text(message).foregroundStyle(.secondary) }
            }

            if model.entries.isEmpty, model.hasLoaded, model.message == nil {
                Section { Text("Nothing found").foregroundStyle(.secondary) }
            }

            ForEach(model.entries) { entry in
                if entry.isSection, let next = entry.navigation {
                    NavigationLink {
                        Component(address: address, url: next, title: entry.title)
                    } label: {
                        section(entry)
                    }
                } else {
                    book(entry)
                }
            }

            if model.next != nil {
                Button {
                    Task { await model.loadMore() }
                } label: {
                    HStack {
                        Text("Show more")
                        Spacer()

                        if model.isLoadingMore { ProgressView() }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(model.isLoadingMore)
                .accessibilityIdentifier("opds.more")
            }
        }

        private func section(_ entry: OPDSEntry) -> some View {
            VStack(alignment: .leading, spacing: Design.Space.extraSmall) {
                Text(entry.title)
                    .font(Design.Style.item)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let summary = entry.summary, !summary.isEmpty {
                    Text(summary)
                        .font(Design.Style.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        /// A book, which can be taken away where the catalogue offers a shape this reader opens.
        ///
        /// One it cannot is still shown: a list that silently dropped them would read as a catalogue
        /// missing books rather than as a book in the wrong wrapping.
        private func book(_ entry: OPDSEntry) -> some View {
            let wanted = entry.preferred(among: FeedModel.wanted)

            return Button {
                Task { await model.take(entry) }
            } label: {
                HStack(spacing: Design.Space.medium) {
                    VStack(alignment: .leading, spacing: Design.Space.extraSmall) {
                        Text(entry.title)
                            .font(Design.Style.item)
                            .foregroundStyle(wanted == nil ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if !entry.authors.isEmpty {
                            Text(entry.authorLine)
                                .font(Design.Style.caption)
                                .foregroundStyle(.secondary)
                        }

                        if wanted == nil {
                            Text("Unsupported")
                                .font(Design.Style.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if model.fetching == entry.id {
                        ProgressView()
                    } else if wanted != nil {
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(wanted == nil || model.fetching != nil)
            .accessibilityHint(wanted == nil ? "" : String(localized: "Adds the book to your library"))
        }
    }
}
