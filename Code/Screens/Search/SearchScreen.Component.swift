//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import SwiftUI

enum SearchScreen {
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
        @Environment(SessionStore.self)
        private var session

        @State
        private var feed: CatalogFeed?

        @State
        private var path: [AppRoute] = []

        @State
        private var searchText = ""

        @State
        private var scope: Scope = .everything

        @State
        private var sorting: CatalogSorting = .popular

        var body: some View {
            NavigationStack(path: $path) {
                Group {
                    if let feed {
                        content(feed)
                    } else {
                        Color.clear
                    }
                }
                .navigationTitle("Search")
                .navigationDestination(for: AppRoute.self) { AppRouteDestination(route: $0) }
            }
            .onAppear {
                if feed == nil { feed = CatalogFeed(client: session.client) }
            }
        }

        @ViewBuilder
        private func content(_ feed: CatalogFeed) -> some View {
            List {
                if !visibleWorks(feed).isEmpty {
                    resultsHeader(feed)
                }

                ForEach(visibleWorks(feed)) { work in
                    Button {
                        path.append(.work(id: work.id, title: work.title))
                    } label: {
                        WorkRow(work: work, showsProgress: false)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isButton)
                    .listRowSeparator(.hidden)
                    .task { await feed.loadMoreIfNeeded(currentItem: work) }
                }

                if feed.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                        .accessibilityLabel("Loading more")
                }
            }
            .listStyle(.plain)
            .accessibilityIdentifier("search.list")
            .searchable(text: $searchText, prompt: "Book title or author name")
            .searchScopes($scope) {
                ForEach(Scope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .onSubmit(of: .search) { Task { await runSearch(feed) } }
            .onChange(of: sorting) { Task { await runSearch(feed) } }
            .onChange(of: searchText) { _, term in
                if term.isEmpty { Task { await runSearch(feed) } }
            }
            .toolbar { sortingMenu }
            .overlay { overlay(feed) }
        }

        private func resultsHeader(_ feed: CatalogFeed) -> some View {
            HStack {
                Text(headerText(feed))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowSeparator(.hidden)
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
        private func visibleWorks(_ feed: CatalogFeed) -> [WorkSummary] {
            let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            guard !term.isEmpty, scope != .everything else { return feed.works }

            return feed.works.filter { work in
                switch scope {
                    case .title: work.title.lowercased().contains(term)
                    case .author: work.authorLine.lowercased().contains(term)
                    case .everything: true
                }
            }
        }

        private func runSearch(_ feed: CatalogFeed) async {
            let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !term.isEmpty else { return }

            await feed.load(CatalogQuery(text: term, pageSize: 30, sorting: sorting))
        }
    }
}
