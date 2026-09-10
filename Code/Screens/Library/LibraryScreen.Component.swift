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

        /// The book being opened and where its cover stands, held only while the reader is going into
        /// it. The shelf draws its own books, so the transition is given a stand-in at that place: a
        /// zoom grows out of a SwiftUI view, and there is no SwiftUI view of a book any more.
        @State
        private var opening: Opening?

        /// The place a book is being opened from.
        private struct Opening: Equatable {
            let id: Int
            let face: CGRect
        }

        /// Where the list stands, so a place on the screen can be given to the stand-in as a place in it.
        @State
        private var listFrame: CGRect = .zero

        /// What the list has to lay cards out in, measured once rather than guessed at.
        @State
        private var listWidth: CGFloat = 0

        /// Whether the shapes earlier runs measured have been read back yet.
        @State
        private var shapesKnown = false

        @Environment(BookOrigins.self)
        private var origins

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

                opening = nil

                Task { await model?.refreshFromStore() }
            }
        }

        @ViewBuilder
        private func content(_ model: Model) -> some View {
            @Bindable var model = model

            shelf(model)
                .background(Design.Surface.screen)
                .safeAreaInset(edge: .bottom) {
                    if model.isSelecting { selectionBar(model) }
                }
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

        /// The library itself: a collection view holding a card for each author.
        ///
        /// Nothing is built until the width is known, since every card's height is worked out from the
        /// books on it and a card laid out against nothing would have to be laid out again.
        @ViewBuilder
        private func shelf(_ model: Model) -> some View {
            ZStack {
                if listWidth > 0, shapesKnown { list(model) }
            }
            // Filling what it is given rather than what it holds: nothing is built until the width is
            // known, and a stack holding nothing has no width to know.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // What shape every cover is, read back before a card is built rather than while it is on
            // screen. A book whose shape nobody has measured is taken for the commonest one, so a shelf
            // laid out before they arrive stands every book at the wrong height and shuffles them all
            // when they land.
            .task {
                await CoverShapes.load()

                shapesKnown = true
            }
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                listWidth = $0.width
                listFrame = $0
            }
            // The stand-in a zoom grows out of, laid over the cover that was tapped and holding still
            // until the reader comes back off the book.
            .overlay(alignment: .topLeading) {
                if let opening {
                    Color.clear
                        .frame(width: opening.face.width, height: opening.face.height)
                        .offset(
                            x: opening.face.minX - listFrame.minX,
                            y: opening.face.minY - listFrame.minY
                        )
                        .matchedTransitionSource(id: opening.id, in: zoom)
                        .allowsHitTesting(false)
                }
            }
        }

        private func list(_ model: Model) -> some View {
            LibraryList(
                cards: cards(model),
                chrome: LibraryList.Chrome(
                    heading: LibraryHeaderView.Contents(
                        title: String(localized: "Library"),
                        showing: model.filter.title,
                        isSelecting: model.isSelecting,
                        isImporting: model.isImporting,
                        merge: mergeDeeds(),
                        filters: filterDeeds(model),
                        onSelect: { model.isSelecting.toggle() },
                        onAdd: { isPickingFile = true }
                    ),
                    search: model.searchText,
                    onSearch: { model.searchText = $0 },
                    empty: emptyShelf(model)
                ),
                onOpen: { work, face in open(model, work: work, from: face) },
                onName: { author in chose(model, author: author) },
                onTurn: { author in switchMode(model, series: author) },
                bookMenu: { bookDeeds(model, work: $0).offered },
                runMenu: { run in
                    model.shelves.flatMap(\.runs).first { $0.id == run }
                        .map { seriesDeeds(model, group: $0).offered } ?? nil
                },
                authorMenu: { author in
                    model.shelves.first { $0.id == author }
                        .map { authorDeeds(model, shelf: $0).offered } ?? nil
                },
                onRefresh: { await model.reload() }
            )
        }

        /// Everything the list draws, worked out from the model rather than by the cards themselves.
        private func cards(_ model: Model) -> [AuthorCardView.Contents] {
            model.shelves.map { shelf in
                AuthorCardView.Contents(
                    id: shelf.id,
                    name: shelf.name,
                    shelf: ShelfView.Contents(
                        runs: shelf.runs.map {
                            ShelfRun(id: $0.id, title: $0.series ?? "", slots: model.slots(of: $0))
                        },
                        alone: shelf.alone.flatMap { model.slots(of: $0) },
                        coverWidth: coverWidth,
                        // Picking books out shows every one of them: a spine is not something to aim
                        // at, and the books being picked are as likely to be read as not.
                        showsEveryCover: model.isSelecting || model.showsEveryCover(shelf.id),
                        isPicked: model.isSelecting ? { model.selection.contains($0.id) } : nil,
                        origin: { origins.origin(of: $0) }
                    ),
                    isPicked: model.isSelecting
                        ? Set(shelf.works.map(\.id)).isSubset(of: model.selection)
                        : nil
                )
            }
        }

        /// What a tap on an author's name does: pick every book of theirs while selecting, else turn
        /// their shelf round.
        private func chose(_ model: Model, author: String) {
            guard let shelf = model.shelves.first(where: { $0.id == author }) else { return }
            guard !model.isSelecting else { return shelf.works.forEach(model.toggle) }

            switchMode(model, series: author)
        }

        // MARK: - The shelf's own heading

        /// Holding two of something together, which only the reader can say to do.
        private func mergeDeeds() -> [Deed] {
            [
                .act(String(localized: "Combine series"), systemImage: "books.vertical") { merging = .series },
                .act(String(localized: "Combine authors"), systemImage: "person.2") { merging = .authors },
            ]
        }

        /// Which books to show, with the one in force ticked.
        private func filterDeeds(_ model: Model) -> [Deed] {
            Model.Filter.allCases.map { filter in
                .act(
                    title(filter, count: model.count(for: filter)),
                    systemImage: filter.systemImage,
                    isOn: model.filter == filter
                ) {
                    model.filter = filter
                }
            }
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

        private func title(_ filter: Model.Filter, count: Int?) -> String {
            guard let count else { return filter.title }

            return "\(filter.title) (\(count))"
        }

        // MARK: - Cards

        /// How wide a cover stands on this screen. One width for the whole library: the size wanted
        /// decides how many fit in a row, and what is there is shared out between that many.
        private var coverWidth: CGFloat {
            let card = listWidth - Design.Space.extraLarge * 2

            return Design.Size.coverWidth(across: card - Design.Space.large * 2, spacing: Shelf.gutter)
        }

        /// Turning a run between its spines and its covers, which every book does on its own hinge.
        private func switchMode(_ model: Model, series: String) {
            guard !model.isSelecting else { return }

            withAnimation(FoldMotion.turning) { model.toggleCovers(of: series) }
        }

        /// Everything of one author's, reachable from their name: each series with what can be done to
        /// it, and the books of theirs that stand in none.
        ///
        /// The card itself shows artwork, which says nothing about which series a book is in or what
        /// order the reader put them in. A bracket carries its own series' actions, but a bracket can
        /// be a few points wide, and one that had to be found before a series could be reordered is
        /// a control the reader has to hunt for.
        private func authorDeeds(_ model: Model, shelf: Model.AuthorShelf) -> [Deed] {
            let runs = shelf.runs.map { group in Deed.menu(group.series ?? "", seriesDeeds(model, group: group)) }
            let alone = shelf.alone.compactMap(\.works.first).map { work in
                Deed.act(work.title, systemImage: "book") { path.append(.work(id: work.id, title: work.title)) }
            }

            return alone.isEmpty ? runs : runs + [ .menu(String(localized: "Books"), alone) ]
        }

        private func seriesDeeds(_ model: Model, group: Model.Group) -> [Deed] {
            // Offered for every series, not only the ones the reader put together. Ordering a series
            // the service named makes it theirs, which is the answer they wanted anyway.
            var deeds: [Deed] = [
                .act(String(localized: "Series details"), systemImage: "list.bullet.rectangle") {
                    path.append(.series(name: group.series ?? ""))
                },
                .act(String(localized: "Reorder books"), systemImage: "arrow.up.arrow.down") {
                    reordering = group
                },
            ]

            // Only a series the reader made can be broken up; the service's own has nothing to undo.
            if group.isCustom {
                deeds.append(.act(
                    String(localized: "Break up this series"),
                    systemImage: "rectangle.split.3x1",
                    isDestructive: true
                ) {
                    Task { await model.ungroup(series: group.series ?? "") }
                })
            }

            return deeds
        }

        private func open(_ work: Book) {
            path.append(.reader(.init(workId: work.id, title: work.title)))
        }

        /// Opening a book off the shelf, which it grows out of.
        ///
        /// The stand-in is put in place first and the book pushed a tick later, since a zoom looks for
        /// its source as the destination arrives and one placed in the same breath is not there yet.
        private func open(_ model: Model, work: Book, from face: CGRect) {
            guard !model.isSelecting else { return model.toggle(work) }

            opening = Opening(id: work.id, face: face)

            Task { @MainActor in open(work) }
        }

        private func bookDeeds(_ model: Model, work: Book) -> [Deed] {
            [
                // The way to the book's own page. A tap on a cover opens the book itself, so without
                // this there is nothing left that reaches what the book is.
                .act(String(localized: "Book details"), systemImage: "info.circle") {
                    path.append(.work(id: work.id, title: work.title))
                },
                .act(
                    String(localized: "Mark as read"),
                    systemImage: "checkmark.circle",
                    isEnabled: !work.isReadToTheEnd
                ) {
                    Task { await model.markAsRead(work) }
                },
                .act(
                    model.isLocal(work)
                        ? String(localized: "Delete this book")
                        : String(localized: "Remove from library"),
                    systemImage: "trash",
                    isDestructive: true
                ) {
                    Task { await model.remove(work) }
                },
            ]
        }

        /// What to say where there is nothing to show, and why there isn't.
        private func emptyShelf(_ model: Model) -> LibraryList.Chrome.Empty? {
            guard !model.isLoading else { return nil }

            return LibraryList.Chrome.Empty(
                title: String(localized: "Nothing here yet"),
                message: model.searchText.isEmpty
                    ? String(
                        localized:
                            "Add books to your library on author.today, or bring an FB2 file in with the plus button."
                    )
                    : String(localized: "Nothing matched your search."),
                systemImage: "books.vertical"
            )
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
