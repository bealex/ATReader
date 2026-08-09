//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import SwiftUI

enum LibraryScreen {
    struct Component: View {
        @Environment(SessionStore.self)
        private var session

        @State
        private var model: Model?

        @State
        private var path: [AppRoute] = []

        var body: some View {
            NavigationStack(path: $path) {
                Group {
                    if let model {
                        content(model)
                    } else {
                        Color.clear
                    }
                }
                .navigationTitle("Library")
                .navigationDestination(for: AppRoute.self) { AppRouteDestination(route: $0) }
            }
            .onAppear {
                if model == nil { model = Model(session: session) }
            }
            .task {
                await model?.loadIfNeeded()
            }
        }

        @ViewBuilder
        private func content(_ model: Model) -> some View {
            @Bindable var model = model

            List {
                if !model.continueReading.isEmpty && model.shelf == nil && model.searchText.isEmpty {
                    continueSection(model)
                }

                Section {
                    if model.visibleWorks.isEmpty {
                        emptyRow(model)
                    } else {
                        ForEach(model.visibleWorks) { work in
                            NavigationLink(value: AppRoute.work(id: work.id, title: work.title)) {
                                WorkRow(work: work, newChapters: model.newChapters(for: work.id))
                            }
                        }
                        .id(model.newChapterRevision)
                    }
                } header: {
                    Text(model.shelf?.title ?? "All books")
                }
            }
            .listStyle(.plain)
            .accessibilityIdentifier("library.list")
            .searchable(text: $model.searchText, prompt: "Title or author")
            .refreshable { await model.reload() }
            .toolbar { shelfMenu(model) }
            .overlay {
                if model.isLoading && !model.hasLoaded {
                    ProgressView("Loading your library…")
                        .accessibilityLabel("Loading your library")
                }
            }
            .alert(
                "Error",
                isPresented: .init(get: { model.errorMessage != nil }, set: { _ in }),
                actions: { Button("OK", role: .cancel, action: {}) },
                message: { Text(model.errorMessage ?? "") }
            )
        }

        private func continueSection(_ model: Model) -> some View {
            Section("Continue reading") {
                ScrollView(.horizontal, showsIndicators: false) {
                    // Lazy on purpose: a plain HStack builds every card up front, which would fetch
                    // covers for books scrolled well off the right-hand edge.
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(model.continueReading) { work in
                            NavigationLink(
                                value: AppRoute.reader(
                                    .init(workId: work.id, title: work.title, chapterId: work.lastChapterId)
                                )
                            ) {
                                ContinueCard(work: work)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
        }

        @ViewBuilder
        private func emptyRow(_ model: Model) -> some View {
            if !model.isLoading {
                ContentUnavailableView(
                    "Nothing here yet",
                    systemImage: "books.vertical",
                    description: Text(
                        model.searchText.isEmpty
                            ? "Add books to your library on author.today and they will show up here."
                            : "Nothing matched your search."
                    )
                )
                .listRowSeparator(.hidden)
            }
        }

        @ToolbarContentBuilder
        private func shelfMenu(_ model: Model) -> some ToolbarContent {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(
                        "Shelf",
                        selection: .init(get: { model.shelf }, set: { model.shelf = $0 }),
                        content: {
                            Text("All books").tag(LibraryState?.none)

                            ForEach(LibraryState.shelves, id: \.self) { state in
                                Label(shelfTitle(state, count: model.count(for: state)), systemImage: state.systemImage)
                                    .tag(LibraryState?.some(state))
                            }
                        }
                    )
                } label: {
                    Label("Shelf", systemImage: "line.3.horizontal.decrease.circle")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel("Choose a shelf")
                .accessibilityHint("Filters your library by shelf")
            }
        }

        private func shelfTitle(_ state: LibraryState, count: Int?) -> String {
            guard let count else { return state.title }

            return "\(state.title) (\(count))"
        }
    }

    /// A compact cover-first card for the "continue reading" strip.
    struct ContinueCard: View {
        let work: WorkSummary

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                CoverImage(url: work.coverURL, width: 92)

                Text(work.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .frame(width: 92, alignment: .leading)

                if let progress = work.readingProgress {
                    ProgressView(value: progress)
                        .frame(width: 92)
                        .tint(.accentColor)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the book at your last chapter")
        }

        private var accessibilityLabel: String {
            guard let percent = WorkFormatting.progress(work.readingProgress) else { return work.title }

            return "\(work.title), \(percent) read"
        }
    }
}

/// Resolves a pushed route into its screen; every stack in the app shares this mapping.
struct AppRouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
            case let .work(id, title):
                WorkScreen.Component(workId: id, title: title)
            case let .reader(reader):
                ReaderScreen.Component(workId: reader.workId, title: reader.title, initialChapterId: reader.chapterId)
        }
    }
}
