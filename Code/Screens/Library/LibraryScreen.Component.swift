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
        /// Shared with the search tab, which shows the same shelves narrowed to what was typed.
        let model: Model

        @Environment(BookInbox.self)
        private var inbox

        @Environment(Navigator.self)
        private var navigator

        /// What the reader is holding together, while they are doing it.
        @State
        private var merging: MergeKind?

        var body: some View {
            Shelves(model: model, search: nil, empty: emptyShelf)
                .background(Design.Surface.screen)
                .navigationTitle(Text("Library"))
                .navigationSubtitle(Text(model.filter.title))
                .toolbar { bar }
                .overlay {
                    // The shelf first, so a full one never waits on whether the library is loading.
                    if model.works.isEmpty && model.isLoading {
                        LoadingOverlay(title: "Loading your library…", label: "Loading your library")
                    }
                }
                .alert(
                    "Error",
                    isPresented: .init(get: { model.errorMessage != nil }, set: { _ in model.dismissError() }),
                    actions: { Button("OK", role: .cancel, action: {}) },
                    message: { Text(model.errorMessage ?? "") }
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
                .task { await model.loadIfNeeded() }
                .onChange(of: inbox.importedAt) { _, _ in
                    // A book picked in the profile, or handed over by another app, lands in the store
                    // rather than in this screen.
                    Task {
                        guard let workId = inbox.lastAccepted else { return await model.refreshFromStore() }

                        await model.adoptImported(workId: workId)
                    }
                }
                .onChange(of: navigator.returnedAt) { _, _ in
                    // Reading fills the rings, and only the store knows it. Coming back off a book redraws
                    // the list from there rather than leaving yesterday's covers up.
                    Task { await model.refreshFromStore() }
                }
        }

        /// What the bar over the shelf offers: holding two things together, and what to show.
        @ToolbarContentBuilder
        private var bar: some ToolbarContent {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    DeedMenu(deeds: mergeDeeds())
                } label: {
                    Label("Combine", systemImage: "arrow.triangle.merge")
                }
                .accessibilityIdentifier("library.merge")
                .accessibilityHint("Holds two series, or two spellings of a name, together")

                Menu {
                    DeedMenu(deeds: filterDeeds())
                } label: {
                    Label("Choose what to show", systemImage: "line.3.horizontal.decrease.circle")
                }
                .accessibilityIdentifier("library.filter")
                .accessibilityHint("Filters your library")
            }
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
        private func filterDeeds() -> [Deed] {
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

        private func title(_ filter: Model.Filter, count: Int?) -> String {
            guard let count else { return filter.title }

            return "\(filter.title) (\(count))"
        }

        /// What to say where there is nothing to show, and why there isn't.
        private var emptyShelf: LibraryList.Chrome.Empty {
            LibraryList.Chrome.Empty(
                title: String(localized: "Nothing here yet"),
                message: String(
                    localized:
                        "Add books to your library on author.today, or bring an FB2 file in with the plus button."
                ),
                systemImage: "books.vertical"
            )
        }
    }

    /// The library as a collection view holding a card for each author, with everything a book, a run and
    /// a name offer. The library tab shows it whole, and the search tab narrowed to what was typed.
    struct Shelves: View {
        let model: Model
        /// The books a search keeps, or `nil` for the whole shelf under its filter.
        let search: ((Book) -> Bool)?
        /// What to say where the shelf comes out empty, once the library has loaded.
        let empty: LibraryList.Chrome.Empty?

        @Environment(Navigator.self)
        private var navigator

        @State
        private var reordering: Model.Group?

        /// The book whose series and volume are being corrected.
        @State
        private var correcting: Book?

        /// What the list has to lay cards out in, measured once rather than guessed at.
        @State
        private var listWidth: CGFloat = 0

        /// Whether the shapes earlier runs measured have been read back yet.
        @State
        private var shapesKnown = false

        /// Nothing is built until the width is known, since every card's height is worked out from the
        /// books on it and a card laid out against nothing would have to be laid out again.
        var body: some View {
            ZStack {
                if listWidth > 0, shapesKnown { list }
            }
            // Filling what it is given rather than what it holds: nothing is built until the width is
            // known, and a stack holding nothing has no width to know.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Under both bars, which then change the collection view's insets rather than its frame: a
            // frame moved by the large title as it grows under a pull shakes the list.
            .ignoresSafeArea(.container, edges: .vertical)
            // What shape every cover is, read back before a card is built rather than while it is on
            // screen. A book whose shape nobody has measured is taken for the commonest one, so a shelf
            // laid out before they arrive stands every book at the wrong height and shuffles them all
            // when they land.
            .task {
                await CoverShapes.load()

                shapesKnown = true
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                listWidth = $0
            }
            .modifier(SeriesEditing(model: model, reordering: $reordering, correcting: $correcting))
        }

        private var shelves: [Model.AuthorShelf] { model.shelves(matching: search) }

        private var list: some View {
            let cards = cards

            // The cards first, so a full shelf never waits on whether the library is loading.
            return LibraryList(
                cards: cards,
                chrome: LibraryList.Chrome(empty: cards.isEmpty && !model.isLoading ? empty : nil),
                onOpen: { work, face in open(work, from: face) },
                onName: { author in chose(author: author) },
                onTurn: { author in switchMode(series: author) },
                // Under the book's own name, so a menu pressed on a spine says which book it is of.
                bookMenu: { bookDeeds(work: $0).offered(under: $0.title, and: $0.series) },
                runMenu: { run in
                    shelves.flatMap(\.runs).first { $0.id == run }
                        .map { seriesDeeds(group: $0).offered } ?? nil
                },
                authorMenu: { author in
                    shelves.first { $0.id == author }
                        .map { authorDeeds(shelf: $0).offered } ?? nil
                },
                onRefresh: { await model.reload() }
            )
        }

        /// Everything the list draws, worked out from the model rather than by the cards themselves.
        private var cards: [AuthorCardView.Contents] {
            shelves.map { shelf in
                AuthorCardView.Contents(
                    id: shelf.id,
                    name: shelf.name,
                    shelf: ShelfView.Contents(
                        runs: shelf.runs.map {
                            ShelfRun(id: $0.id, title: $0.series ?? "", slots: model.slots(of: $0))
                        },
                        alone: shelf.alone.flatMap { model.slots(of: $0) },
                        coverWidth: coverWidth,
                        showsEveryCover: model.showsEveryCover(shelf.id)
                    )
                )
            }
        }

        /// What a tap on an author's name does, which is turn their shelf round.
        private func chose(author: String) {
            guard shelves.contains(where: { $0.id == author }) else { return }

            switchMode(series: author)
        }

        // MARK: - Cards

        /// How wide a cover stands on this screen. One width for the whole library: the size wanted
        /// decides how many fit in a row, and what is there is shared out between that many.
        private var coverWidth: CGFloat {
            let card = listWidth - Design.Space.extraLarge * 2

            return Design.Size.coverWidth(across: card - Design.Space.large * 2, spacing: Shelf.gutter)
        }

        /// Turning a run between its spines and its covers, which every book does on its own hinge.
        private func switchMode(series: String) {
            withAnimation(FoldMotion.turning) { model.toggleCovers(of: series) }
        }

        /// Everything of one author's, reachable from their name: each series with what can be done to
        /// it, and the books of theirs that stand in none.
        ///
        /// The card itself shows artwork, which says nothing about which series a book is in or what
        /// order the reader put them in. A bracket carries its own series' actions, but a bracket can
        /// be a few points wide, and one that had to be found before a series could be reordered is
        /// a control the reader has to hunt for.
        private func authorDeeds(shelf: Model.AuthorShelf) -> [Deed] {
            let runs = shelf.runs.map { group in Deed.menu(group.series ?? "", seriesDeeds(group: group)) }
            let alone = shelf.alone.compactMap(\.works.first).map { work in
                Deed.act(work.title, systemImage: "book") { navigator.push(.work(id: work.id, title: work.title)) }
            }

            let books = alone.isEmpty ? runs : runs + [ .menu(String(localized: "Books"), alone) ]

            return books + [ hiding(shelf: shelf) ]
        }

        /// Taking a writer off the Reading shelf. They keep their card everywhere else, so this says
        /// what the reader is working through rather than what they own.
        private func hiding(shelf: Model.AuthorShelf) -> Deed {
            let hidden = model.hiddenFromReading.contains(shelf.key)

            return .act(
                hidden ? String(localized: "Show in Reading") : String(localized: "Hide from Reading"),
                systemImage: hidden ? "eye" : "eye.slash"
            ) {
                model.setHidden(!hidden, author: shelf.key)
            }
        }

        private func seriesDeeds(group: Model.Group) -> [Deed] {
            // Offered for every series, not only the ones the reader put together. Ordering a series
            // the service named makes it theirs, which is the answer they wanted anyway.
            var deeds: [Deed] = [
                .act(String(localized: "Series details"), systemImage: "list.bullet.rectangle") {
                    navigator.push(.series(name: group.series ?? ""))
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

        /// Opening a book off the shelf, which it grows out of: the very board its artwork is on.
        private func open(_ work: Book, from face: UIView) {
            navigator.push(.reader(.init(workId: work.id, title: work.title)), from: face)
        }

        private func bookDeeds(work: Book) -> [Deed] {
            [
                // Reaches a book standing on its edge, which a tap only turns round with its run.
                .act(String(localized: "Read the book"), systemImage: "book") {
                    Task { await model.takeDown(work) }
                    navigator.push(.reader(.init(workId: work.id, title: work.title)))
                },
                // The way to the book's own page. A tap on a cover opens the book itself, so without
                // this there is nothing left that reaches what the book is.
                .act(String(localized: "Book details"), systemImage: "info.circle") {
                    navigator.push(.work(id: work.id, title: work.title))
                },
                .act(
                    String(localized: "Mark as read"),
                    systemImage: "checkmark.circle",
                    isEnabled: !work.isReadToTheEnd
                ) {
                    Task { await model.markAsRead(work) }
                },
                .act(String(localized: "Series and volume"), systemImage: "number") { correcting = work },
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
    }
}

/// Reordering a series and correcting one book's series and volume, kept off the shelf's own body.
private struct SeriesEditing: ViewModifier {
    let model: LibraryScreen.Model

    @Binding
    var reordering: LibraryScreen.Model.Group?

    @Binding
    var correcting: Book?

    func body(content: Content) -> some View {
        content
            .sheet(item: $reordering) { group in
                SeriesOrder(group: group) { ids in
                    Task { await model.reorder(series: group.series ?? "", workIds: ids) }
                }
            }
            .sheet(item: $correcting) { work in
                SeriesEditor(
                    work: work,
                    writersSeries: SeriesCorrection.writersSeries(of: work, among: model.works)
                ) { edit in
                    Task { await model.correctSeries(of: work, to: edit) }
                }
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
            case .readerAppearance:
                ReaderScreen.Appearance()
            #if DEBUG
                case .designSystem:
                    DesignSystemScreen.Component()
            #endif
        }
    }
}
