//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import SwiftUI
import UniformTypeIdentifiers

enum LibraryScreen {
    struct Component: View {
        @Environment(SessionStore.self)
        private var session

        @Environment(BookInbox.self)
        private var inbox

        @State
        private var model: Model?

        @State
        private var path: [AppRoute] = []

        @State
        private var isPickingFile = false

        var body: some View {
            NavigationStack(path: $path) {
                Group {
                    if let model {
                        content(model)
                    } else {
                        Color.clear
                    }
                }
                // The shelf carries its own heading, so the bar above it would only repeat the word.
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: AppRoute.self) { AppRouteDestination(route: $0) }
            }
            .onAppear {
                if model == nil { model = Model(session: session) }
            }
            .task {
                await model?.loadIfNeeded()
            }
            .onChange(of: inbox.importedAt) { _, _ in
                // A book handed over by another app lands in the store rather than in this screen.
                Task { await model?.refreshFromStore() }
            }
            .onChange(of: path) { _, current in
                // Reading fills the rings, and only the store knows it. Coming back off a book redraws
                // the list from there rather than leaving yesterday's covers up.
                guard current.isEmpty else { return }

                Task { await model?.refreshFromStore() }
            }
        }

        @ViewBuilder
        private func content(_ model: Model) -> some View {
            @Bindable var model = model

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    heading(model)
                    search(model)

                    if model.groups.isEmpty {
                        empty(model)
                    } else {
                        ForEach(model.groups) { group in
                            if group.series != nil {
                                seriesCard(model, group: group)
                            } else if let work = group.works.first {
                                card { bookRow(model, work: work) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .accessibilityIdentifier("library.list")
            .refreshable { await model.reload() }
            .fileImporter(
                isPresented: $isPickingFile,
                allowedContentTypes: Self.bookTypes,
                allowsMultipleSelection: true
            ) { result in
                guard case let .success(urls) = result else { return }

                Task {
                    for url in urls { await model.importBook(from: url) }
                }
            }
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

        /// FB2 has no type of its own on the system, so it is named by its extension. XML is offered
        /// beside it because a file saved from a browser often arrives typed as that instead.
        private static var bookTypes: [UTType] {
            [ UTType(filenameExtension: "fb2"), .xml ].compactMap { $0 }
        }

        // MARK: - The shelf's own heading

        private func heading(_ model: Model) -> some View {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Library")
                        .font(.largeTitle.bold())

                    Text(model.filter.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                addButton(model)
                filterMenu(model)
            }
            .padding(.top, 8)
            .accessibilityElement(children: .contain)
        }

        private func addButton(_ model: Model) -> some View {
            Button {
                isPickingFile = true
            } label: {
                Image(systemName: model.isImporting ? "hourglass" : "plus")
                    .font(.title3)
                    .frame(width: 34, height: 34)
            }
            .disabled(model.isImporting)
            .accessibilityIdentifier("library.add")
            .accessibilityLabel("Add a book from a file")
            .accessibilityHint("Reads an FB2 file into your library")
        }

        private func filterMenu(_ model: Model) -> some View {
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
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.title3)
                    .frame(width: 34, height: 34)
            }
            .accessibilityLabel("Choose what to show")
            .accessibilityHint("Filters your library")
        }

        private func title(_ filter: Model.Filter, count: Int?) -> String {
            guard let count else { return filter.title }

            return "\(filter.title) (\(count))"
        }

        /// The shelf's own field rather than the navigation bar's, which went with the bar.
        private func search(_ model: Model) -> some View {
            @Bindable var model = model

            return HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                TextField("Title or author", text: $model.searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Search your library")

                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear the search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }

        // MARK: - Cards

        /// A series is one card holding its books, so a run of them reads as a set rather than as
        /// separate books that happen to sit together.
        private func seriesCard(_ model: Model, group: Model.Group) -> some View {
            card {
                VStack(alignment: .leading, spacing: 0) {
                    seriesHeader(group)

                    ForEach(Array(group.works.enumerated()), id: \.element.id) { index, work in
                        if index > 0 {
                            Divider().padding(.leading, 12)
                        }

                        bookRow(model, work: work)
                    }
                }
            }
        }

        private func seriesHeader(_ group: Model.Group) -> some View {
            HStack(spacing: 8) {
                Image(systemName: "books.vertical.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text(group.series ?? "")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text("\(group.works.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }

        private func card(@ViewBuilder _ content: () -> some View) -> some View {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        }

        /// A button rather than a `NavigationLink`: a link is what draws the disclosure chevron.
        private func bookRow(_ model: Model, work: WorkSummary) -> some View {
            Button {
                path.append(.work(id: work.id, title: work.title))
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    WorkRow(work: work, showsSeries: false, newChapters: model.newChapters(for: work.id))

                    if let progress = model.processing[work.id] {
                        preparing(progress)
                    }
                }
                .padding(12)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .contextMenu { bookActions(model, work: work) }
        }

        /// A book being put through the typesetter says so. It is readable while this runs.
        private func preparing(_ progress: BookProcessor.Progress) -> some View {
            ProgressView(value: progress.fraction) {
                Text("Preparing \(progress.prepared) of \(progress.total) chapters…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Preparing this book, \(progress.prepared) of \(progress.total) chapters done")
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
                Label(model.isLocal(work) ? "Delete this book" : "Remove from library", systemImage: "trash")
            }
        }

        @ViewBuilder
        private func empty(_ model: Model) -> some View {
            if !model.isLoading {
                ContentUnavailableView(
                    "Nothing here yet",
                    systemImage: "books.vertical",
                    description: Text(
                        model.searchText.isEmpty
                            ? "Add books to your library on author.today, or bring an FB2 file in with the plus button."
                            : "Nothing matched your search."
                    )
                )
                .padding(.top, 40)
            }
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
