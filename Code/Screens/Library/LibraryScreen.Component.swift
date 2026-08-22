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
                if !model.continueReading.isEmpty && model.searchText.isEmpty {
                    continueSection(model)
                }

                if model.groups.isEmpty {
                    emptyRow(model)
                } else {
                    ForEach(model.groups) { group in
                        Section {
                            ForEach(group.works) { work in
                                bookRow(model, work: work)
                            }
                        } header: {
                            groupHeader(group)
                        }
                    }
                    .id(model.newChapterRevision)
                }
            }
            .listStyle(.plain)
            .accessibilityIdentifier("library.list")
            .navigationSubtitle(model.shelf?.title ?? String(localized: "All books"))
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
                isPresented: .init(get: { model.errorMessage != nil }, set: { _ in model.dismissError() }),
                actions: { Button("OK", role: .cancel, action: {}) },
                message: { Text(model.errorMessage ?? "") }
            )
        }

        /// A button rather than a `NavigationLink`: a link is what draws the disclosure chevron.
        private func bookRow(_ model: Model, work: WorkSummary) -> some View {
            Button {
                path.append(.work(id: work.id, title: work.title))
            } label: {
                WorkRow(work: work, showsSeries: false, newChapters: model.newChapters(for: work.id))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .contextMenu { shelfActions(model, work: work) }
        }

        @ViewBuilder
        private func groupHeader(_ group: Model.Group) -> some View {
            VStack(alignment: .leading, spacing: 1) {
                Text(group.author)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if let series = group.series {
                    Text(series)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .textCase(nil)
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        }

        @ViewBuilder
        private func shelfActions(_ model: Model, work: WorkSummary) -> some View {
            ForEach(LibraryState.shelves, id: \.self) { state in
                Button {
                    Task { await model.move(work, to: state) }
                } label: {
                    Label(state.title, systemImage: state.systemImage)
                }
                .disabled(work.libraryState == state)
            }

            Divider()

            Button(role: .destructive) {
                Task { await model.move(work, to: .none) }
            } label: {
                Label("Remove from library", systemImage: "trash")
            }
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

    /// The cover alone, with the reader's position on it.
    struct ContinueCard: View {
        let work: WorkSummary

        var body: some View {
            CoverImage(url: work.coverURL, width: 92, progress: work.readingProgress)
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
