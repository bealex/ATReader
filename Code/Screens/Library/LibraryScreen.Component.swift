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
                if model.groups.isEmpty {
                    emptyRow(model)
                } else {
                    ForEach(model.groups) { group in
                        Section {
                            ForEach(group.works) { work in
                                bookRow(model, work: work)
                            }
                        } header: {
                            if let series = group.series { seriesHeader(series) }
                        }
                    }
                    .id(model.newChapterRevision)
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(.compact)
            .accessibilityIdentifier("library.list")
            .navigationSubtitle(model.filter.title)
            .searchable(text: $model.searchText, prompt: "Title or author")
            .refreshable { await model.reload() }
            .toolbar { filterMenu(model) }
            .overlay {
                if model.isLoading && model.works.isEmpty {
                    LoadingOverlay(title: "Loading your library…", label: "Loading your library")
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
            .listRowSeparator(.hidden)
            .contextMenu { bookActions(model, work: work) }
        }

        /// The series a run of books belongs to. Its own row insets keep it close to them: the header's
        /// default gap reads as a break between sections rather than a name over a list.
        private func seriesHeader(_ series: String) -> some View {
            Text(series)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .textCase(nil)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 2, trailing: 16))
                .accessibilityAddTraits(.isHeader)
        }

        @ViewBuilder
        private func bookActions(_ model: Model, work: WorkSummary) -> some View {
            Button {
                Task { await model.markAsRead(work) }
            } label: {
                Label("Mark as read", systemImage: "checkmark.circle")
            }
            .disabled(work.isReadToTheEnd)

            Button(role: .destructive) {
                Task { await model.remove(work) }
            } label: {
                Label("Remove from library", systemImage: "trash")
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
        private func filterMenu(_ model: Model) -> some ToolbarContent {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(
                        "Show",
                        selection: .init(get: { model.filter }, set: { model.filter = $0 }),
                        content: {
                            ForEach(Model.Filter.allCases) { filter in
                                Label(title(filter, count: model.count(for: filter)), systemImage: filter.systemImage)
                                    .tag(filter)
                            }
                        }
                    )
                } label: {
                    Label("Show", systemImage: "line.3.horizontal.decrease.circle")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel("Choose what to show")
                .accessibilityHint("Filters your library")
            }
        }

        private func title(_ filter: Model.Filter, count: Int?) -> String {
            guard let count else { return filter.title }

            return "\(filter.title) (\(count))"
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
