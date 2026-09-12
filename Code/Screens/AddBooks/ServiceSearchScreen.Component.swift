//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import BookKit
import DesignSystem
import SwiftUI

/// Searching the service's catalogue from the Add books sheet.
///
/// A book here is not taken away as a file, the way one from a catalogue is: the service keeps its
/// books and hands over a chapter at a time. So what a hit offers is the book's own page, and the
/// sheet closes on the way, since the page it opens stands behind it.
enum ServiceSearchScreen {
    struct Component: View {
        @Binding
        var isPresented: Bool

        @Environment(SessionStore.self)
        private var session

        @Environment(Navigator.self)
        private var navigator

        @State
        private var feed: CatalogFeed?

        @State
        private var term = ""

        var body: some View {
            List {
                if let feed {
                    if let message = feed.errorMessage {
                        Section { Text(message).foregroundStyle(.secondary) }
                    }

                    if feed.isEmpty, feed.hasLoaded {
                        Section { Text("Nothing found").foregroundStyle(.secondary) }
                    }

                    ForEach(feed.works) { work in
                        row(work)
                    }
                }
            }
            .navigationTitle(Text(verbatim: "author.today"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $term, prompt: Text("Title or author"))
            .onSubmit(of: .search) { search() }
            .overlay {
                if feed?.isLoading == true { ProgressView().controlSize(.large) }
            }
            .onAppear { if feed == nil { feed = CatalogFeed(client: session.client) } }
        }

        private func row(_ work: Book) -> some View {
            Button {
                open(work)
            } label: {
                VStack(alignment: .leading, spacing: Design.Space.extraSmall) {
                    Text(work.title)
                        .font(Design.Style.item)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !work.authorLine.isEmpty {
                        Text(work.authorLine)
                            .font(Design.Style.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the book’s page")
        }

        /// Closes the sheet, then opens the book behind it.
        ///
        /// In that order and a beat apart: the page is pushed onto the stack the sheet is standing in
        /// front of, and pushing it first would put it somewhere nobody can see.
        private func open(_ work: Book) {
            isPresented = false

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                navigator.push(.work(id: work.id, title: work.title))
            }
        }

        private func search() {
            let term = term.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !term.isEmpty, let feed else { return }

            Task { await feed.load(CatalogQuery(text: term, pageSize: 30)) }
        }
    }
}
