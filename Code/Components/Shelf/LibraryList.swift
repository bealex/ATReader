//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import DesignSystem
import SwiftUI
import UIKit

/// The library, as one collection view with a card for each author.
///
/// A card's height is worked out from the books on it before the card is built, so the list never has to
/// ask a cell how big it is, and cells are reused, so a library of five hundred books costs whatever is
/// on screen.
struct LibraryList: UIViewControllerRepresentable {
    /// What the list holds besides the cards.
    struct Chrome {
        /// What to say where there is nothing to show. Nothing while the library is still loading.
        let empty: Empty?

        /// The shelf with nothing on it, and why.
        struct Empty {
            let title: String
            let message: String
            let systemImage: String
        }
    }

    let cards: [AuthorCardView.Contents]
    let chrome: Chrome
    let onOpen: (Book, UIView) -> Void
    /// A tap on the author's name, which turns their shelf round or picks every book of theirs out.
    let onName: (String) -> Void
    /// A tap on a book standing on its edge, which turns the shelf it is on.
    let onTurn: (String) -> Void
    let bookMenu: (Book) -> UIMenu?
    let runMenu: (String) -> UIMenu?
    let authorMenu: (String) -> UIMenu?
    let onRefresh: () async -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UICollectionViewController {
        context.coordinator.make()
    }

    func updateUIViewController(_ controller: UICollectionViewController, context: Context) {
        context.coordinator.show(self)
    }

    /// What the list is made of, in the order it stands in.
    enum Section: Hashable {
        case empty
        case author(String)
    }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
        private var list: LibraryList
        private var controller: UICollectionViewController?
        private var source: UICollectionViewDiffableDataSource<Section, Section>?
        /// Which way round each card's books last stood, so a card whose books turned is turned rather
        /// than rebuilt.
        private var shown: [String: [String: Bool]] = [:]
        /// The card in the middle of a turn, and the two heights it is travelling between.
        private var carrying: Carrying?
        /// A refresh that finished while the finger was still pulling, left to end once it lets go.
        private var endsRefreshingOnRelease = false
        /// How tall each card stands across the width it was measured at, and the shape of the shelf it
        /// was measured for. A layout asks for every card on every pass, and on every frame of a turn.
        private var measured: [String: (shape: Int, height: CGFloat)] = [:]
        private var measuredAcross: CGFloat = 0

        /// A card on its way from one height to another. It holds the card itself rather than looking
        /// it up: the height is asked for in the middle of a layout, and a collection view hands out no
        /// cells while it is laying out.
        private struct Carrying {
            let id: String
            let from: CGFloat
            let to: CGFloat
            weak var card: AuthorCardView?

            var reached: CGFloat { card?.reached ?? 1 }
        }

        /// How many books the shelf makes before anyone scrolls: a few screens' worth of cards.
        private static let preparedBooks = 150

        init(_ list: LibraryList) {
            self.list = list
        }

        func make() -> UICollectionViewController {
            let controller = UICollectionViewController(collectionViewLayout: layout())

            controller.collectionView.backgroundColor = UIColor(Design.Surface.screen)
            controller.collectionView.delegate = self
            controller.collectionView.prefetchDataSource = self
            controller.collectionView.accessibilityIdentifier = "library.list"
            controller.collectionView.keyboardDismissMode = .interactive
            controller.collectionView.refreshControl = UIRefreshControl(
                frame: .zero,
                primaryAction: UIAction { [weak self] _ in self?.refresh() }
            )
            source = make(controller.collectionView)
            self.controller = controller

            // The stand-ins every book shows until its own pictures arrive, printed before any is asked for.
            for isDark in [ false, true ] {
                _ = CoverPrint.blank(isDark: isDark)
                _ = SpinePrint.blank(isDark: isDark)
                _ = BookcasePrint.lid(isDark: isDark)
                _ = BookcasePrint.corner(isDark: isDark)
            }

            apply(animated: false)
            press()
            ShelfView.prepare(upTo: Self.preparedBooks)

            return controller
        }

        func show(_ list: LibraryList) {
            let turned = self.list.cards.count == list.cards.count
            // How tall each card stands now, read before the new contents replace the old: a card
            // carried to another height has to set out from the one it actually has, and asking
            // afterwards asks about the height it is going to.
            let standing = heights(across: cardWidth)

            self.list = list
            measure(across: cardWidth)

            apply(animated: false)
            press()

            guard let source else { return }

            for card in list.cards {
                guard let index = source.indexPath(for: .author(card.id)) else { continue }
                guard let cell = controller?.collectionView.cellForItem(at: index) as? AuthorCardCell else { continue }

                let was = shown[card.id]
                let stance = ShelfView.stance(of: card.shelf)

                shown[card.id] = stance
                dress(cell, with: card)

                // Only a card whose books have turned is animated. Everything else is a redraw, and a
                // redraw that springs would move every book on screen whenever one cover loaded.
                if turned, let was, was != stance {
                    turn(cell, to: card, from: standing[card.id])
                } else {
                    cell.card.show(card)
                }
            }
        }

        /// Carries one card to the height its books are turning towards, and everything below it along
        /// with it, on the turn's own clock.
        ///
        /// The height is asked for again on every frame of the turn rather than animated. A collection
        /// view will not carry a compositional layout from one set of heights to another: whichever way
        /// the change is made it recomputes them and puts every card where it is going in one frame.
        private func turn(_ cell: AuthorCardCell, to card: AuthorCardView.Contents, from standing: CGFloat?) {
            let across = cardWidth

            carrying = Carrying(
                id: card.id,
                from: standing ?? height(of: card.id, across: across) ?? 0,
                to: measured[card.id]?.height ?? AuthorCardView.height(card, across: across),
                card: cell.card
            )
            cell.card.onFrame = { [weak self] in
                guard let self else { return }

                controller?.collectionView.collectionViewLayout.invalidateLayout()

                if cell.card.reached >= 1 { carrying = nil }
            }
            cell.card.turn(to: card, animated: true)
        }

        /// The width a card is laid out across, which is the list's own less the insets either side.
        private var cardWidth: CGFloat {
            (controller?.collectionView.bounds.width ?? 0) - Design.Space.extraLarge * 2
        }

        /// What every card on the list stands at, for whoever needs them before they change.
        private func heights(across: CGFloat) -> [String: CGFloat] {
            list.cards.reduce(into: [:]) { heights, card in
                heights[card.id] = height(of: card.id, across: across)
            }
        }

        /// What a card stands at across the width it is given, which is its own height except while it
        /// is turning, when it is somewhere between the two.
        private func height(of id: String, across: CGFloat) -> CGFloat? {
            if let carrying, carrying.id == id {
                return carrying.from + (carrying.to - carrying.from) * carrying.reached
            }

            if measuredAcross != across { measure(across: across) }

            return measured[id]?.height
        }

        /// Works out every card's height, keeping the ones whose shelves still stand the way they did.
        /// Run when the cards change, which is also when the filter or a search changes them.
        private func measure(across: CGFloat) {
            if measuredAcross != across {
                measured.removeAll(keepingCapacity: true)
                measuredAcross = across
            }

            let typeSize = controller?.collectionView.traitCollection.preferredContentSizeCategory
            var kept: [String: (shape: Int, height: CGFloat)] = [:]

            for card in list.cards {
                var hasher = Hasher()

                hasher.combine(card.name)
                hasher.combine(typeSize)
                ShelfView.shape(of: card.shelf, into: &hasher)

                let shape = hasher.finalize()

                if let held = measured[card.id], held.shape == shape {
                    kept[card.id] = held
                } else {
                    kept[card.id] = (shape, AuthorCardView.height(card, across: across))
                }
            }

            measured = kept
        }

        private func refresh() {
            Task {
                await list.onRefresh()
                endRefreshing()
            }
        }

        /// Puts the spinner away, but never under a finger: ending a refresh mid-pull jumps the list.
        private func endRefreshing() {
            guard let collection = controller?.collectionView else { return }

            if collection.isDragging {
                endsRefreshingOnRelease = true
            } else {
                collection.refreshControl?.endRefreshing()
            }
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard endsRefreshingOnRelease else { return }

            endsRefreshingOnRelease = false
            scrollView.refreshControl?.endRefreshing()
        }

        // MARK: - Ahead of the reader

        /// Prints the whole library's spines before it is scrolled, so a card coming into view blits
        /// pictures rather than running a blur for every book on it.
        private func press() {
            guard let collection = controller?.collectionView else { return }

            SpinePress.press(
                list.cards.flatMap { ShelfView.spines(in: $0.shelf) },
                isDark: collection.traitCollection.userInterfaceStyle == .dark
            )
        }

        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            let coming = cards(at: indexPaths)
            let isDark = collectionView.traitCollection.userInterfaceStyle == .dark

            SpinePress.warm(coming.flatMap { ShelfView.covers(in: $0.shelf) })
            CoverPrint.warm(coming.flatMap { ShelfView.faces(in: $0.shelf, isDark: isDark) })
        }

        /// A card coming into view asks again for whatever it gave up while it was away.
        func collectionView(
            _ collectionView: UICollectionView,
            willDisplay cell: UICollectionViewCell,
            forItemAt indexPath: IndexPath
        ) {
            (cell as? AuthorCardCell)?.card.shelf.resumeLoading()
        }

        /// A card that has left the screen stops decoding and printing for books nobody can see.
        func collectionView(
            _ collectionView: UICollectionView,
            didEndDisplaying cell: UICollectionViewCell,
            forItemAt indexPath: IndexPath
        ) {
            (cell as? AuthorCardCell)?.card.shelf.pauseLoading()
        }

        private func cards(at paths: [IndexPath]) -> [AuthorCardView.Contents] {
            paths.compactMap { path in
                guard case let .author(id) = source?.sectionIdentifier(for: path.section) else { return nil }

                return list.cards.first { $0.id == id }
            }
        }

        // MARK: - What stands where

        private func layout() -> UICollectionViewLayout {
            UICollectionViewCompositionalLayout { [weak self] index, environment in
                self?.section(index, across: environment.container.effectiveContentSize.width)
                    ?? Self.section(height: .estimated(Design.Size.touch))
            }
        }

        private func section(_ index: Int, across available: CGFloat) -> NSCollectionLayoutSection {
            guard
                let section = source?.sectionIdentifier(for: index)
            else { return Self.section(height: .estimated(Design.Size.touch)) }

            switch section {
                case .empty:
                    return Self.section(height: .estimated(Design.Size.avatar * 4))
                case let .author(id):
                    let across = available - Design.Space.extraLarge * 2

                    guard
                        let deep = height(of: id, across: across)
                    else { return Self.section(height: .estimated(Design.Size.touch)) }

                    // Given rather than measured. A cell that answers with its own height sends the
                    // layout round again to ask, and a height that is moving never gives the same
                    // answer twice: the collection view goes round until it trips over itself.
                    return Self.section(height: .absolute(max(1, deep)))
            }
        }

        private static func section(height: NSCollectionLayoutDimension) -> NSCollectionLayoutSection {
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: height)
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: size,
                subitems: [ NSCollectionLayoutItem(layoutSize: size) ]
            )
            let section = NSCollectionLayoutSection(group: group)

            section.contentInsets = NSDirectionalEdgeInsets(
                top: 0,
                leading: Design.Space.extraLarge,
                bottom: Design.Space.large,
                trailing: Design.Space.extraLarge
            )

            return section
        }

        // MARK: - What is in it

        private func make(_ view: UICollectionView) -> UICollectionViewDiffableDataSource<Section, Section> {
            let nothing = UICollectionView.CellRegistration<UICollectionViewCell, Section> { [weak self] cell, _, _ in
                guard let empty = self?.list.chrome.empty else { return cell.contentConfiguration = nil }

                var shown = UIContentUnavailableConfiguration.empty()

                shown.image = UIImage(systemName: empty.systemImage)
                shown.text = empty.title
                shown.secondaryText = empty.message
                cell.contentConfiguration = shown
            }

            let card = UICollectionView.CellRegistration<AuthorCardCell, String> { [weak self] cell, _, id in
                guard let self, let contents = list.cards.first(where: { $0.id == id }) else { return }

                dress(cell, with: contents)
                cell.card.show(contents)
                shown[id] = ShelfView.stance(of: contents.shelf)
            }

            return UICollectionViewDiffableDataSource(collectionView: view) { view, index, section in
                switch section {
                    case let .author(id):
                        view.dequeueConfiguredReusableCell(using: card, for: index, item: id)
                    case .empty:
                        view.dequeueConfiguredReusableCell(using: nothing, for: index, item: section)
                }
            }
        }

        /// Everything a card does when it is touched, which the cell forgets whenever it is reused.
        private func dress(_ cell: AuthorCardCell, with contents: AuthorCardView.Contents) {
            cell.card.onName = { [weak self] in self?.list.onName(contents.id) }
            cell.card.nameMenu = { [weak self] in self?.list.authorMenu(contents.id) }
            cell.card.shelf.onToggle = { [weak self] in self?.list.onTurn(contents.id) }
            cell.card.shelf.onOpen = { [weak self] work, face in self?.list.onOpen(work, face) }
            cell.card.shelf.bookMenu = { [weak self] work in self?.list.bookMenu(work) }
            cell.card.shelf.runMenu = { [weak self] run in self?.list.runMenu(run) }
        }

        private func apply(animated: Bool) {
            guard let source else { return }

            var snapshot = NSDiffableDataSourceSnapshot<Section, Section>()

            if list.cards.isEmpty {
                snapshot.appendSections([ .empty ])
                snapshot.appendItems([ .empty ], toSection: .empty)
            } else {
                for card in list.cards {
                    snapshot.appendSections([ .author(card.id) ])
                    snapshot.appendItems([ .author(card.id) ], toSection: .author(card.id))
                }
            }

            source.apply(snapshot, animatingDifferences: animated)
        }
    }
}

/// One author's card, in a cell that can be handed to the next author when this one scrolls away.
final class AuthorCardCell: UICollectionViewCell {
    let card = AuthorCardView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        card.frame = contentView.bounds
        card.autoresizingMask = [ .flexibleWidth, .flexibleHeight ]
        contentView.addSubview(card)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
