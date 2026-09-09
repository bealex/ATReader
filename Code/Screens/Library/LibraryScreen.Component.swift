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

        /// What the reader is holding together, while they are doing it.
        @State
        private var merging: MergeKind?

        /// Where a cover stands, so the reader opens into the book from its own artwork.
        @Namespace
        private var zoom

        /// What the shelf has to lay books out in, measured once rather than guessed at.
        @State
        private var shelfWidth: CGFloat = 0

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
                .navigationDestination(for: AppRoute.self) { route in
                    // A book grows out of the cover that was tapped and settles back into it on the
                    // way out. Only from the shelf, which is the only place holding the artwork.
                    if case let .reader(reader) = route {
                        AppRouteDestination(route: route)
                            .navigationTransition(.zoom(sourceID: reader.workId, in: zoom))
                    } else {
                        AppRouteDestination(route: route)
                    }
                }
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
                .sheet(item: $merging) { kind in
                    switch kind {
                        case .series:
                            MergeSheet(title: "Combine series", choices: Self.runs(of: model)) { picked, name in
                                let runs = model.allSeries.filter { picked.contains($0.id) }

                                Task { await model.merge(runs, named: name) }
                            }
                        case .authors:
                            MergeSheet(title: "Combine authors", choices: Self.writers(of: model)) { picked, name in
                                Task { await model.mergeAuthors(picked, as: name) }
                            }
                    }
                }
        }

        private func shelf(_ model: Model) -> some View {
            LazyVStack(alignment: .leading, spacing: Design.Space.large) {
                heading(model)
                search(model)

                if model.shelves.isEmpty {
                    empty(model)
                } else {
                    ForEach(model.shelves) { shelf in authorCard(model, shelf: shelf) }
                }
            }
            // Measured before the padding goes on, so what is read is the width the cards actually
            // get. Read afterwards, it hands the padding back and lays every cover out too wide.
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                shelfWidth = $0
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

                mergeButton
                selectButton(model)
                addButton(model)
                filterMenu(model)
            }
            .padding(.top, Design.Space.medium)
            .accessibilityElement(children: .contain)
        }

        /// Holding two of something together, which only the reader can say to do.
        private var mergeButton: some View {
            Menu {
                Button {
                    merging = .series
                } label: {
                    Label("Combine series", systemImage: "books.vertical")
                }

                Button {
                    merging = .authors
                } label: {
                    Label("Combine authors", systemImage: "person.2")
                }
            } label: {
                Image(systemName: "arrow.triangle.merge")
                    .barGlyph()
                    .contentShape(.rect)
            }
            .accessibilityIdentifier("library.merge")
            .accessibilityLabel("Combine")
            .accessibilityHint("Holds two series, or two spellings of a name, together")
        }

        /// The library's series, as things that can be held together.
        private static func runs(of model: Model) -> [MergeChoice] {
            model.allSeries.map {
                MergeChoice(id: $0.id, title: $0.series ?? "", detail: $0.author ?? "", count: $0.works.count)
            }
        }

        private static func writers(of model: Model) -> [MergeChoice] {
            model.authors.map { MergeChoice(id: $0.name, title: $0.name, detail: "", count: $0.count) }
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
        /// Everything of one author's: their series, held together by a line apiece, and then the
        /// books of theirs that belong to no series.
        private func authorCard(_ model: Model, shelf: Model.AuthorShelf) -> some View {
            card {
                VStack(alignment: .leading, spacing: Design.Space.medium) {
                    authorHeader(model, shelf: shelf)

                    AuthorShelfView(
                        runs: shelf.runs.map {
                            ShelfRun(id: $0.id, title: $0.series ?? "", slots: model.slots(of: $0))
                        },
                        alone: shelf.alone.flatMap { model.slots(of: $0) },
                        coverWidth: coverWidth,
                        available: shelfWidth - Design.Space.large * 2,
                        // Picking books out shows every one of them: a spine is not something to aim
                        // at, and the books being picked are as likely to be read as not.
                        showsEveryCover: model.isSelecting || model.showsEveryCover(shelf.id),
                        zoom: zoom,
                        isPicked: model.isSelecting ? { model.selection.contains($0.id) } : nil,
                        onToggle: { switchMode(model, series: shelf.id) },
                        onOpen: { work in
                            guard !model.isSelecting else { return model.toggle(work) }

                            open(work)
                        },
                        actions: { work in bookActions(model, work: work) },
                        runActions: { series in
                            if let group = shelf.runs.first(where: { $0.id == series.id }) {
                                seriesActions(model, group: group)
                            }
                        }
                    )
                    .padding(.horizontal, Design.Space.large)
                    .padding(.bottom, Design.Space.large)
                }
            }
        }

        /// How wide a cover stands on this screen. One width for the whole library: the size wanted
        /// decides how many fit in a row, and what is there is shared out between that many.
        private var coverWidth: CGFloat {
            Design.Size.coverWidth(across: shelfWidth - Design.Space.large * 2, spacing: Shelf.gutter)
        }

        /// Swapping between covers and spines, which is one movement rather than a redraw.
        private func switchMode(_ model: Model, series: String) {
            guard !model.isSelecting else { return }

            withAnimation(.snappy) { model.toggleCovers(of: series) }
        }

        private func authorHeader(_ model: Model, shelf: Model.AuthorShelf) -> some View {
            HStack(spacing: Design.Space.medium) {
                if model.isSelecting {
                    tick(Set(shelf.works.map(\.id)).isSubset(of: model.selection))
                }

                Text(shelf.name)
                    .font(Design.Style.heading)
                    .lineLimit(2)

                Spacer(minLength: Shelf.gutter)
            }
            .padding(.horizontal, Design.Space.large)
            .padding(.top, Design.Space.medium)
            .contentShape(.rect)
            .onTapGesture {
                guard !model.isSelecting else { return shelf.works.forEach(model.toggle) }

                switchMode(model, series: shelf.id)
            }
            .contextMenu { authorActions(model, shelf: shelf) }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Switches between every cover and the books left to read")
        }

        /// Everything of one author's, reachable from their name: each series with what can be done to
        /// it, and the books of theirs that stand in none.
        ///
        /// The card itself shows artwork, which says nothing about which series a book is in or what
        /// order the reader put them in. A bracket carries its own series' actions, but a bracket can
        /// be a few points wide, and one that had to be found before a series could be reordered is
        /// a control the reader has to hunt for.
        @ViewBuilder
        private func authorActions(_ model: Model, shelf: Model.AuthorShelf) -> some View {
            ForEach(shelf.runs) { group in
                Menu(group.series ?? "") { seriesActions(model, group: group) }
            }

            if !shelf.alone.isEmpty {
                Menu("Books") {
                    ForEach(shelf.alone) { group in
                        if let work = group.works.first {
                            Button(work.title) { path.append(.work(id: work.id, title: work.title)) }
                        }
                    }
                }
            }
        }

        @ViewBuilder
        private func seriesActions(_ model: Model, group: Model.Group) -> some View {
            // Offered for every series, not only the ones the reader put together. Ordering a series
            // the service named makes it theirs, which is the answer they wanted anyway.
            Button {
                path.append(.series(name: group.series ?? ""))
            } label: {
                Label("Series details", systemImage: "list.bullet.rectangle")
            }

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

        /// A book as a line of the shelf. Inside a series card the heading already names the series,
        /// so only a book standing on its own repeats it.
        private func bookRow(
            _ model: Model,
            work: Book,
            number: Int?,
            title: String,
            showsSeries: Bool = false,
            seriesAuthor: String? = nil,
            coverWidth: CGFloat = Design.Size.rowCover
        ) -> some View {
            HStack(spacing: Design.Space.medium) {
                if model.isSelecting { tick(model.selection.contains(work.id)) }

                VStack(alignment: .leading, spacing: Design.Space.small) {
                    BookRow(
                        work: work,
                        coverWidth: coverWidth,
                        showsSeries: showsSeries,
                        showsAuthor: seriesAuthor == nil || seriesAuthor != work.authorLine,
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
            .padding(.horizontal, Design.Space.large)
            .padding(.vertical, Design.Space.medium)
            .contentShape(.rect)
            .onTapGesture { choose(model, work: work) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Read") { open(work) }
            .contextMenu { bookActions(model, work: work) }
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
            LineGlyph(systemImage: isOn ? "checkmark.circle.fill" : "circle")
                .font(Design.Control.barGlyph)
                .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
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
            // The way to the book's own page. A tap on a cover opens the book itself, so without this
            // there is nothing left that reaches what the book is.
            Button {
                path.append(.work(id: work.id, title: work.title))
            } label: {
                Label("Book details", systemImage: "info.circle")
            }

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
                .padding(.top, Design.Space.section)
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
            case let .series(name):
                SeriesScreen.Component(series: name)
        }
    }
}
