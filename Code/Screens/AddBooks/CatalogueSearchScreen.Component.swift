//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import DesignSystem
import OPDS
import SwiftUI

/// Searching one OPDS catalogue, and taking a book out of it.
///
/// The address is the reader's own, since every library has its own, and the last one they used is
/// kept so they are not asked for it twice.
enum CatalogueSearchScreen {
    /// Where the catalogue the reader last used is remembered.
    static let addressKey = "opds.address"

    struct Component: View {
        @AppStorage(CatalogueSearchScreen.addressKey)
        private var address = ""

        @Environment(BookInbox.self)
        private var inbox

        @State
        private var model = FeedModel()

        @State
        private var scope: CatalogueScope = .books

        @State
        private var term = ""

        var body: some View {
            List {
                catalogue
                asking

                OPDSFeedScreen.Rows(model: model, address: address)
            }
            .navigationTitle("OPDS library")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if model.isLoading { ProgressView().controlSize(.large) }
            }
            .onAppear { model.inbox = inbox }
        }

        private var catalogue: some View {
            Section {
                TextField("Catalogue address", text: $address)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .accessibilityIdentifier("opds.address")
            } header: {
                Text("Catalogue")
            } footer: {
                Text("The address of a library that speaks OPDS. It is remembered for next time.")
            }
        }

        /// What is being looked for, and the asking itself.
        ///
        /// Nothing is searched for until the button is pressed. A catalogue is somebody else's server
        /// and often a slow one, and a search for every letter typed is a search for every letter
        /// typed. While one is running the whole section is held still, and the button is where the
        /// waiting is shown, since that is where the reader last looked.
        private var asking: some View {
            Section {
                Picker("What to look for", selection: $scope) {
                    ForEach(CatalogueScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.isLoading)
                .accessibilityIdentifier("opds.scope")

                HStack(spacing: Design.Space.medium) {
                    TextField(scope.prompt, text: $term)
                        .autocorrectionDisabled()
                        .disabled(model.isLoading)
                        .accessibilityIdentifier("opds.term")
                        .onSubmit { ask() }

                    if model.isLoading {
                        ProgressView()
                    } else {
                        Button(action: ask) {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(.borderless)
                        .disabled(isBlank)
                        .accessibilityLabel("Search")
                        .accessibilityIdentifier("opds.search")
                    }
                }
            }
        }

        private var isBlank: Bool { term.trimmingCharacters(in: .whitespaces).isEmpty }

        private func ask() {
            guard !isBlank, !model.isLoading else { return }

            let term = term
            let address = address

            Task {
                switch scope {
                    case .books: await model.search(term, at: address)
                    case .authors, .series: await model.open(scope, beginning: term, at: address)
                }
            }
        }
    }
}
