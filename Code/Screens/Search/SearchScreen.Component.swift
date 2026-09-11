//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import AuthorTodayBooks
import BookKit
import DesignSystem
import SwiftUI

enum SearchScreen {
    /// Where the typed term is looked for.
    enum Source: String, CaseIterable, Identifiable {
        /// The reader's own shelves, answered on the device as the term is typed.
        case library
        /// The service's catalogue, asked when the term is submitted.
        case authorToday

        var id: String { rawValue }
    }

    /// How the typed term is matched. The service searches titles and author names together, so the
    /// narrower modes filter the answer locally rather than asking a different endpoint.
    enum Scope: String, CaseIterable, Identifiable {
        case everything
        case title
        case author

        var id: String { rawValue }

        var title: String {
            switch self {
                case .everything: "Everywhere"
                case .title: "Title"
                case .author: "Author"
            }
        }
    }

    struct Component: View {
        /// The library tab's own model, so a book found here is the book on the shelf.
        let library: LibraryScreen.Model

        @Environment(SessionStore.self)
        private var session

        @State
        private var feed: CatalogFeed?

        @Environment(Navigator.self)
        private var navigator

        @State
        private var source: Source = .library

        @State
        private var searchText = ""

        /// The term the catalogue was last asked for, so switching back to it doesn't ask again.
        @State
        private var searched = ""

        @State
        private var scope: Scope = .everything

        @State
        private var sorting: CatalogSorting = .popular

        var body: some View {
            Group {
                switch source {
                    case .library:
                        libraryResults
                    case .authorToday:
                        if let feed { catalogResults(feed) } else { Color.clear }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { bar }
            .searchable(text: $searchText, prompt: "Book title or author name")
            .searchScopes($scope) {
                ForEach(Scope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .onSubmit(of: .search) { Task { await runSearch() } }
            .onChange(of: source) { Task { await runSearch() } }
            .onChange(of: sorting) { Task { await runSearch(again: true) } }
            .onAppear {
                if feed == nil { feed = CatalogFeed(client: session.client) }
            }
        }

        @ToolbarContentBuilder
        private var bar: some ToolbarContent {
            ToolbarItem(placement: .principal) {
                Picker("Search", selection: $source) {
                    Text("Library").tag(Source.library)
                    Text(verbatim: "Author.Today").tag(Source.authorToday)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityIdentifier("search.source")
            }

            if source == .authorToday { sortingMenu }
        }

        private var term: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        // MARK: - The reader's own shelves

        /// The library's own shelves, narrowed to what was typed.
        @ViewBuilder
        private var libraryResults: some View {
            if term.isEmpty {
                ContentUnavailableView(
                    "Search your library",
                    systemImage: "books.vertical",
                    description: Text("Enter a book title or an author’s name.")
                )
            } else {
                let search = matching(term)

                LibraryScreen.Shelves(model: library, search: search, empty: nil)
                    .background(Design.Surface.screen)
                    .overlay {
                        if library.hasLoaded, library.shelves(matching: search).isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        }
                    }
            }
        }

        /// Which books answer a lowercased term within the scope. Everywhere takes in a book's series
        /// too, since a reader looking for one names it.
        private func matching(_ term: String) -> (Book) -> Bool {
            let scope = scope

            return { work in
                switch scope {
                    case .title: work.title.lowercased().contains(term)
                    case .author: work.authorLine.lowercased().contains(term)
                    case .everything:
                        work.title.lowercased().contains(term)
                            || work.authorLine.lowercased().contains(term)
                            || work.seriesTitle?.lowercased().contains(term) == true
                }
            }
        }

        // MARK: - The service's catalogue

        @ViewBuilder
        private func catalogResults(_ feed: CatalogFeed) -> some View {
            List {
                if !visibleWorks(feed).isEmpty {
                    resultsHeader(feed)
                }

                ForEach(visibleWorks(feed)) { work in
                    Button {
                        navigator.push(.work(id: work.id, title: work.title))
                    } label: {
                        BookRow(work: work, showsProgress: false)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isButton)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .task { await feed.loadMoreIfNeeded(currentItem: work) }
                }

                if feed.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .accessibilityLabel("Loading more")
                }
            }
            .listStyle(.plain)
            .listOnScreen()
            .accessibilityIdentifier("search.list")
            .overlay { overlay(feed) }
        }

        private func resultsHeader(_ feed: CatalogFeed) -> some View {
            HStack {
                Text(headerText(feed))
                    .font(Design.Style.caption)
                    .foregroundStyle(.secondary)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .accessibilityLabel(headerText(feed))
        }

        private func headerText(_ feed: CatalogFeed) -> String {
            guard let total = feed.totalCount, total > 0 else { return "Results" }

            return "Found: \(total.formatted(.number))"
        }

        @ViewBuilder
        private func overlay(_ feed: CatalogFeed) -> some View {
            if feed.isLoading {
                LoadingCard(title: "Searching…", label: "Searching")
            } else if let message = feed.errorMessage {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(message))
            } else if !feed.hasLoaded {
                ContentUnavailableView(
                    "What to read?",
                    systemImage: "magnifyingglass",
                    description: Text("Enter a book title or an author’s name.")
                )
            } else if visibleWorks(feed).isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }

        private var sortingMenu: some ToolbarContent {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(
                        "Sort",
                        selection: $sorting,
                        content: {
                            ForEach(CatalogSorting.allCases, id: \.self) { order in
                                Text(order.title).tag(order)
                            }
                        }
                    )
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel("Sort results")
                .accessibilityHint("Changes the order of the results")
            }
        }

        /// The author/title scopes narrow the service's combined answer on the device.
        private func visibleWorks(_ feed: CatalogFeed) -> [Book] {
            guard !term.isEmpty, scope != .everything else { return feed.works }

            return feed.works.filter(matching(term))
        }

        /// Asks the catalogue for the typed term, unless it was the last thing asked for.
        private func runSearch(again: Bool = false) async {
            guard source == .authorToday, let feed else { return }

            let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !term.isEmpty, again || term != searched else { return }

            searched = term
            await feed.load(CatalogQuery(text: term, pageSize: 30, sorting: sorting))
        }
    }
}
