//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookStorage
import DesignSystem
import SwiftUI

/// Every way a book gets onto this device, in one place.
///
/// The ways differ enough that each is its own row rather than one search across all of them: a file
/// is picked, a Litres shelf is brought across whole, and a catalogue is searched a book at a time.
/// What they share is where they land, which is why they are set out together.
enum AddBooksScreen {
    struct Component: View {
        @Binding
        var isPresented: Bool

        @Environment(BookInbox.self)
        private var inbox

        @State
        private var isPickingFile = false

        var body: some View {
            NavigationStack {
                List {
                    fromAFile
                    fromLitres
                    fromACatalogue
                }
                .navigationTitle("Add books")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Close") { isPresented = false }
                    }
                }
            }
        }

        private var fromAFile: some View {
            Section {
                Button {
                    isPickingFile = true
                } label: {
                    Label("Add a book from a file", systemImage: "doc.badge.plus")
                }
                .disabled(inbox.isImporting)
                .accessibilityIdentifier("add.file")
                .accessibilityHint("Reads an FB2 file into your library")
                .fileImporter(
                    isPresented: $isPickingFile,
                    allowedContentTypes: LocalBookFiles.fileTypes,
                    allowsMultipleSelection: true
                ) { result in
                    guard case let .success(urls) = result else { return }

                    Task { await inbox.accept(urls) }
                }
            } header: {
                Text("From this device")
            } footer: {
                Text("A book from a file lives on this device alone, along with the file it came in.")
            }
        }

        private var fromLitres: some View {
            Section {
                LitresRows()
            } header: {
                Text("Litres")
            } footer: {
                Text("Litres books come across once. The session ends when they arrive.")
            }
        }
        private var fromACatalogue: some View {
            Section {
                NavigationLink {
                    CatalogueSearchScreen.Component()
                } label: {
                    Label("Search an OPDS library", systemImage: "books.vertical")
                }
                .accessibilityIdentifier("add.opds")
                .accessibilityHint("Searches a library you give the address of")

                NavigationLink {
                    ServiceSearchScreen.Component(isPresented: $isPresented)
                } label: {
                    Label("Search author.today", systemImage: "magnifyingglass")
                }
                .accessibilityIdentifier("add.service")
                .accessibilityHint("Searches the service's catalogue")
            } header: {
                Text("From a catalogue")
            } footer: {
                Text(
                    "Books are searched for one at a time. A library's book comes across as a file; the service keeps its own and hands over its page."
                )
            }
        }
    }
}
