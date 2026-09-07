//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import AuthorTodayBooks
import BookKit
import BookRenderer
import BookStorage
import DesignSystem
import SwiftUI

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

        @State
        private var isNamingSeries = false

        @State
        private var seriesName = ""

        @State
        private var reordering: Model.Group?

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

            ScrollView { shelf(model) }
                .background(Design.Surface.screen)
                .safeAreaInset(edge: .bottom) {
                    if model.isSelecting { selectionBar(model) }
                }
                .accessibilityIdentifier("library.list")
                .refreshable { await model.reload() }
                .fileImporter(
                    isPresented: $isPickingFile,
                    allowedContentTypes: LocalBookFiles.fileTypes,
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
                .modifier(
                    SeriesEditing(model: model, reordering: $reordering, isNaming: $isNamingSeries, name: $seriesName)
                )
        }

        private func shelf(_ model: Model) -> some View {
            LazyVStack(alignment: .leading, spacing: Design.Space.large) {
                heading(model)
                search(model)

                if model.groups.isEmpty {
                    empty(model)
                } else {
                    ForEach(model.groups) { group in
                        if group.series != nil {
                            seriesCard(model, group: group)
                        } else if let work = group.works.first {
                            // A book standing on its own has no series to be numbered within.
                            card { bookRow(model, work: work, number: nil, title: work.title) }
                        }
                    }
                }
            }
            .padding(.horizontal, Design.Space.extraLarge)
            .padding(.bottom, Design.Space.huge)
        }

        // MARK: - The shelf's own heading

        private func heading(_ model: Model) -> some View {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Design.Space.extraSmall) {
                    Text("Library")
                        .font(Design.Style.screenTitle)

                    Text(model.filter.title)
                        .font(Design.Style.label)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                selectButton(model)
                addButton(model)
                filterMenu(model)
            }
            .padding(.top, Design.Space.medium)
            .accessibilityElement(children: .contain)
        }

        private func selectButton(_ model: Model) -> some View {
            Button {
                model.isSelecting.toggle()
            } label: {
                Image(systemName: model.isSelecting ? "xmark" : "checklist")
                    .barGlyph()
            }
            .accessibilityIdentifier("library.select")
            .accessibilityLabel(model.isSelecting ? "Stop picking books" : "Pick books out")
            .accessibilityHint("Combines the books you pick into one series")
        }

        /// What the shelf offers while books are being picked out.
        private func selectionBar(_ model: Model) -> some View {
            HStack {
                Text("\(model.selection.count) selected")
                    .font(Design.Style.label)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Combine into a series") {
                    seriesName = Self.suggestedName(model)
                    isNamingSeries = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selection.count < 2)
                .accessibilityIdentifier("library.combine")
            }
            .padding(.horizontal, Design.Space.extraLarge)
            .padding(.vertical, Design.Space.large)
            .background(.bar)
        }

        /// A series already among the picked books names the new one, since combining usually means
        /// adding a book to a series that already exists.
        private static func suggestedName(_ model: Model) -> String {
            model.groups
                .first { $0.series != nil && $0.works.contains { model.selection.contains($0.id) } }?
                .series ?? ""
        }

        private func addButton(_ model: Model) -> some View {
            Button {
                isPickingFile = true
            } label: {
                Image(systemName: model.isImporting ? "hourglass" : "plus")
                    .barGlyph()
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
                    .barGlyph()
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

            return HStack(spacing: Design.Space.medium) {
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
            .padding(.horizontal, Design.Space.large)
            .padding(.vertical, Design.Space.medium)
            .background(Design.Surface.card, in: .rect(cornerRadius: Design.Radius.medium))
        }

        // MARK: - Cards

        /// A series is one card holding its books, so a run of them reads as a set rather than as
        /// separate books that happen to sit together.
        private func seriesCard(_ model: Model, group: Model.Group) -> some View {
            card {
                VStack(alignment: .leading, spacing: 0) {
                    seriesHeader(model, group: group)

                    ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Divider().padding(.leading, Design.Space.large)
                        }

                        switch row {
                            case let .book(work, number, title):
                                if isBehindTheReader(model, work: work) {
                                    finishedRow(model, work: work, number: number, title: title)
                                } else {
                                    bookRow(model, work: work, number: number, title: title)
                                }
                            case let .missing(number):
                                missingRow(number)
                        }
                    }
                }
            }
        }

        private func seriesHeader(_ model: Model, group: Model.Group) -> some View {
            HStack(spacing: Design.Space.medium) {
                if model.isSelecting {
                    tick(Set(group.works.map(\.id)).isSubset(of: model.selection))
                }

                Image(systemName: "books.vertical.fill")
                    .font(Design.Style.caption)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text(group.series ?? "")
                    .font(Design.Style.heading)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text("\(group.works.count)")
                    .font(Design.Style.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                // A button rather than a long press alone: a series has to say that its order is the
                // reader's to set, and a context menu says nothing until it is found.
                if !model.isSelecting { seriesMenu(model, group: group) }
            }
            .padding(.horizontal, Design.Space.large)
            .padding(.top, Design.Space.large)
            .padding(.bottom, Design.Space.medium)
            .contentShape(.rect)
            .onTapGesture {
                guard model.isSelecting else { return }

                model.toggle(group: group)
            }
            .contextMenu { seriesActions(model, group: group) }
            .accessibilityElement(children: .contain)
        }

        private func seriesMenu(_ model: Model, group: Model.Group) -> some View {
            Menu {
                seriesActions(model, group: group)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
                    .barGlyph()
                    .contentShape(.rect)
            }
            .accessibilityIdentifier("series.menu")
            .accessibilityLabel("Series actions")
            .accessibilityHint("Reorders the books in this series, or breaks it up")
        }

        @ViewBuilder
        private func seriesActions(_ model: Model, group: Model.Group) -> some View {
            // Offered for every series, not only the ones the reader put together. Ordering a series
            // the service named makes it theirs, which is the answer they wanted anyway.
            Button {
                reordering = group
            } label: {
                Label("Reorder books", systemImage: "arrow.up.arrow.down")
            }

            // Only a series the reader made can be broken up; the service's own has nothing to undo.
            if group.isCustom {
                Button(role: .destructive) {
                    Task { await model.ungroup(series: group.series ?? "") }
                } label: {
                    Label("Break up this series", systemImage: "rectangle.split.3x1")
                }
            }
        }

        private func card(@ViewBuilder _ content: () -> some View) -> some View {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Design.Surface.card, in: .rect(cornerRadius: Design.Radius.large))
        }

        /// One book on the shelf. The cover opens it; everything else opens its page.
        ///
        /// Two tap targets rather than a button and a link, since the row is the larger of the two and
        /// the cover sits inside it: a gesture on the cover is the inner one, and the inner one wins.
        /// A volume between two the reader holds that is not on the shelf. Not a book, so not a row
        /// anything happens on: it is here to show the run is broken.
        private func missingRow(_ number: Int) -> some View {
            HStack(spacing: Design.Space.medium) {
                SeriesNumber(number: number)

                Text("Not in your library")
                    .font(Design.Style.label)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                Spacer(minLength: Design.Space.medium)
            }
            .padding(.horizontal, Design.Space.large)
            .padding(.vertical, Design.Space.medium)
            .foregroundStyle(.tertiary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Book \(number), not in your library")
        }

        private func bookRow(_ model: Model, work: Book, number: Int?, title: String) -> some View {
            HStack(spacing: Design.Space.medium) {
                if model.isSelecting { tick(model.selection.contains(work.id)) }

                VStack(alignment: .leading, spacing: Design.Space.small) {
                    BookRow(
                        work: work,
                        showsSeries: false,
                        number: number,
                        shortTitle: title,
                        newChapters: model.newChapters(for: work.id),
                        // Selecting books is the whole row's job, so the cover gives up its own tap.
                        onOpenCover: model.isSelecting ? nil : { open(work) }
                    )

                    if let progress = model.processing[work.id] {
                        preparing(progress)
                    }
                }
            }
            .padding(Design.Space.large)
            .contentShape(.rect)
            .onTapGesture { choose(model, work: work) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Read") { open(work) }
            .contextMenu { bookActions(model, work: work) }
        }

        /// A book in a series the reader has finished with, set as one line.
        ///
        /// A long series is read in order, so the ones behind the reader only have to stay findable.
        /// Given a cover and three lines each they push the book actually being read off the screen.
        private func finishedRow(_ model: Model, work: Book, number: Int?, title: String) -> some View {
            HStack(spacing: Design.Space.medium) {
                if model.isSelecting { tick(model.selection.contains(work.id)) }

                Image(systemName: "checkmark.circle.fill")
                    .font(Design.Style.caption)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                if let number { SeriesNumber(number: number) }

                Text(title)
                    .font(Design.Style.label)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, Design.Space.large)
            .padding(.vertical, Design.Space.medium)
            .contentShape(.rect)
            .onTapGesture { choose(model, work: work) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(work.title), read")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Read") { open(work) }
            .contextMenu { bookActions(model, work: work) }
        }

        /// True where the reader is done with this book and nothing new has arrived in it.
        ///
        /// Read to the end of a book still being written doesn't count: the next chapter is what the
        /// reader is waiting for, and a collapsed row is the wrong place to be told it landed.
        private func isBehindTheReader(_ model: Model, work: Book) -> Bool {
            work.isFinishedReading && model.newChapters(for: work.id) == 0
        }

        /// What a tap on the body of a row does: pick the book while selecting, else open its page.
        private func choose(_ model: Model, work: Book) {
            if model.isSelecting {
                model.toggle(work)
            } else {
                path.append(.work(id: work.id, title: work.title))
            }
        }

        private func open(_ work: Book) {
            path.append(.reader(.init(workId: work.id, title: work.title)))
        }

        private func tick(_ isOn: Bool) -> some View {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(Design.Control.barGlyph)
                .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .accessibilityHidden(true)
        }

        /// A book being put through the typesetter says so. It is readable while this runs.
        private func preparing(_ progress: BookProcessor.Progress) -> some View {
            ProgressView(value: progress.fraction) {
                Text("Preparing \(progress.prepared) of \(progress.total) chapters…")
                    .font(Design.Style.micro)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Preparing this book, \(progress.prepared) of \(progress.total) chapters done")
        }

        @ViewBuilder
        private func bookActions(_ model: Model, work: Book) -> some View {
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

/// Naming a new series and reordering an existing one, kept off the shelf's own body.
private struct SeriesEditing: ViewModifier {
    let model: LibraryScreen.Model

    @Binding
    var reordering: LibraryScreen.Model.Group?
    @Binding
    var isNaming: Bool
    @Binding
    var name: String

    func body(content: Content) -> some View {
        content
            .sheet(item: $reordering) { group in
                SeriesOrder(group: group) { ids in
                    Task { await model.reorder(series: group.series ?? "", workIds: ids) }
                }
            }
            .alert("Name this series", isPresented: $isNaming) {
                TextField("Series name", text: $name)
                Button("Combine") {
                    Task { await model.combineSelection(named: name) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The books you picked are shown together under this name.")
            }
    }
}

/// The books of one series, dragged into the order they should be read in.
///
/// The order is only written when the reader is done, so a drag that turns out wrong costs nothing.
struct SeriesOrder: View {
    let group: LibraryScreen.Model.Group
    let onSave: ([Int]) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State
    private var works: [Book] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(works) { work in
                    VStack(alignment: .leading, spacing: Design.Space.extraSmall) {
                        Text(work.title)

                        Text(work.authorLine)
                            .font(Design.Style.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                .onMove { picked, destination in works.move(fromOffsets: picked, toOffset: destination) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(group.series ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(works.map(\.id))
                        dismiss()
                    }
                    .accessibilityIdentifier("series.done")
                }
            }
        }
        .onAppear { works = group.works }
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
