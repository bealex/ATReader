//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import DesignSystem
import UIKit

/// One author's books, standing where `ShelfLayout` puts them.
///
/// Every book keeps its own view for as long as it is on this shelf, so a run turning from spines to
/// covers moves the books that were already there rather than throwing them away and drawing new ones.
/// That is the reason this is not a collection view: a book that lands in a different row when the shelf
/// refolds is the same book, and only a layout owning all of them can say so.
final class ShelfView: UIView {
    /// What stands on the shelf, and which way round.
    struct Contents {
        let runs: [ShelfRun]
        let alone: [SeriesSlot]
        let coverWidth: CGFloat
        /// True while every book stands as a cover, false while the ones read stand as spines.
        let showsEveryCover: Bool
    }

    /// One place on the shelf: a slot and the run it stands in.
    private struct Place {
        let slot: SeriesSlot
        let run: String?

        var id: String { slot.id }
    }

    var onToggle: (() -> Void)?
    /// Called on every frame of a turn, for whatever has to follow the shelf as it changes height.
    var onFrame: (() -> Void)?
    /// A book being opened, and the face it grows out of.
    /// Opening a book, and how to find the face it is standing on at the moment anyone asks.
    ///
    /// A closure rather than the view itself: a zoom asks for the source again on the way out, and by
    /// then the shelf may have laid itself out afresh around whatever the reading changed. The view
    /// that was tapped is the wrong size by then, or belongs to another book entirely.
    var onOpen: ((Book, @escaping @MainActor @Sendable (BookZoom) -> UIView?) -> Void)?
    var bookMenu: ((Book) -> UIMenu?)?
    var runMenu: ((String) -> UIMenu?)?

    private var contents: Contents?
    private var places: [Place] = []
    private var layout = ShelfLayout(tiles: [], slot: 0, across: 0, gutter: 0)
    private var books: [String: BookView] = [:]
    /// How wide the shelf was last drawn for, since a shelf that changes width has nowhere to carry a
    /// turn from.
    private var drawnAcross: CGFloat = 0
    private var turning: Turning?
    private var link: CADisplayLink?
    private var brackets: [String: BracketView] = [:]
    private let bookcase = BookcaseView()
    /// Books taken off a shelf, kept to stand the next ones in on any shelf. A card is handed to another
    /// author whole, and building a book costs more than dressing one again.
    private static var spare: [BookView] = []

    /// Gives up every picture on its way, for a shelf that has left the screen.
    func pauseLoading() {
        for book in books.values { book.stopLoading() }
    }

    /// Asks again for the pictures given up while the shelf was off the screen.
    func resumeLoading() {
        for book in books.values { book.resumeLoading() }
    }

    /// How far round each book on the shelf stands, which is what a turn moves.
    var turns: [String: CGFloat] { books.mapValues(\.turned) }

    /// How far in from either end of the bookcase the books stand.
    static let inset = Design.Space.large

    /// The width the books are laid out across, which is the bookcase's less its ends.
    private var across: CGFloat { bounds.width - Self.inset * 2 }

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(bookcase)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ contents: Contents) {
        // A shelf told to stand a different way round without being asked to turn lands wherever it had
        // got to. Anything else, a cover arriving or a book's progress moving, leaves a turn running.
        if self.contents?.showsEveryCover != contents.showsEveryCover { land() }

        self.contents = contents
        places = Self.places(contents)

        setNeedsLayout()
    }

    /// Ends whatever turn is in flight, leaving the books wherever the layout puts them.
    private func land() {
        link?.invalidate()
        link = nil
        turning = nil
    }

    /// Turns every book on the shelf, and carries the ones the refold puts somewhere else to where they
    /// are going. One clock drives both, so a book that moves turns while it moves.
    func turn(to contents: Contents, animated: Bool) {
        guard animated, bounds.width > 0 else { return show(contents) }

        // Where everything actually stands, rather than where the last turn was going: a turn started
        // while another is running has to carry the books on from where they had reached.
        var was: [String: CGRect] = [:]

        for (id, view) in books { was[id] = view.frame }

        for (id, view) in brackets { was[id] = view.frame }

        let from = books.mapValues(\.turned)
        let wasHeight = layout.height

        self.contents = contents
        places = Self.places(contents)

        let staying = Set(places.map(\.id))

        for (id, view) in books where !staying.contains(id) { fadeAway(view) }

        layout = Self.layout(contents, places: places, across: across)
        build(contents)

        turning = Turning(started: CACurrentMediaTime(), from: from, was: was, wasHeight: wasHeight)
        link?.invalidate()
        link = CADisplayLink(target: self, selector: #selector(stepped))
        link?.add(to: .main, forMode: .common)
        stand()
    }

    /// A book leaving the shelf fades where it stood rather than vanishing from under the ones closing up.
    private func fadeAway(_ view: BookView) {
        guard let ghost = view.snapshotView(afterScreenUpdates: false) else { return }

        ghost.frame = view.frame
        insertSubview(ghost, belowSubview: view)

        UIView.animate(withDuration: FoldMotion.turningSeconds / 2) {
            ghost.alpha = 0
        } completion: { _ in
            ghost.removeFromSuperview()
        }
    }

    /// A turn in flight: when it started, how far round each book was, where each stood, and how deep
    /// the shelf was before it began.
    private struct Turning {
        let started: CFTimeInterval
        let from: [String: CGFloat]
        let was: [String: CGRect]
        let wasHeight: CGFloat
    }

    @objc
    private func stepped() {
        stand()
        onFrame?()

        guard progress >= 1 else { return }

        link?.invalidate()
        link = nil
        turning = nil
    }

    /// How far through the turn the shelf is, for whatever has to keep pace with it.
    var reached: CGFloat { progress }

    /// How deep the shelf stands part way through a turn, and nothing at all when it isn't turning.
    ///
    /// Its own depth rather than the one it is going to: whatever holds a shelf has to be that tall now,
    /// or the books turn inside a box that changed size in one frame. A shelf standing still answers
    /// nothing, since its depth is then a plain question about its books that anyone can ask without it.
    var turningHeight: CGFloat? {
        guard let turning else { return nil }

        return turning.wasHeight + (layout.height - turning.wasHeight) * progress
    }

    /// How far through the turn the shelf is, eased the way a hinge settles: fast to begin with and
    /// slowing to a stop rather than arriving at speed.
    private var progress: CGFloat {
        guard let turning else { return 1 }

        let ran = (CACurrentMediaTime() - turning.started) / FoldMotion.turningSeconds

        return Self.settling(min(1, max(0, ran)))
    }

    /// A critically damped spring, normalised so it arrives exactly.
    private static func settling(_ ran: CGFloat) -> CGFloat {
        let shape = { (time: CGFloat) in 1 - (1 + 8 * time) * exp(-8 * time) }

        return shape(ran) / shape(1)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard let contents, bounds.width > 0 else { return }

        if drawnAcross != bounds.width {
            drawnAcross = bounds.width
            land()
        }

        layout = Self.layout(contents, places: places, across: across)
        bookcase.frame = bounds
        bookcase.slot = layout.slot
        build(contents)
        stand()
    }

    /// How tall this shelf comes out, before any of it is built, across the whole bookcase's width.
    static func height(_ contents: Contents, across available: CGFloat) -> CGFloat {
        layout(contents, places: places(contents), across: available - inset * 2).height
    }

    /// Every spine this shelf will ask for, at the size it will ask for it.
    ///
    /// Every book on it, not only the ones standing on edge: a card turned round wants all of its
    /// spines at once, and how thick a book is doesn't depend on which way round it stands.
    static func spines(in contents: Contents) -> [SpinePress.Wanted] {
        let slot = slotHeight(contents)

        return places(contents).compactMap { place in
            guard case let .book(work, number, title, _) = place.slot else { return nil }

            return SpinePress.Wanted(
                id: work.id,
                coverURL: work.coverURL,
                number: number,
                title: title,
                size: CGSize(
                    width: edgeWidth(of: place.slot, in: contents),
                    height: standing(place.slot, in: contents, slot: slot)
                )
            )
        }
    }

    /// Which way round each place on the shelf stands, true for a cover.
    static func stance(of contents: Contents) -> [String: Bool] {
        places(contents).reduce(into: [:]) { stance, place in
            stance[place.id] = standsAsCover(place.slot, in: contents)
        }
    }

    /// Everything a shelf's height turns on: which books stand where and which way round, how wide a
    /// cover is, and what shape each cover is known to be. Two contents that hash alike stand alike.
    static func shape(of contents: Contents, into hasher: inout Hasher) {
        hasher.combine(contents.coverWidth)

        for place in places(contents) {
            hasher.combine(place.id)
            hasher.combine(place.run)
            hasher.combine(standsAsCover(place.slot, in: contents))

            if case let .book(work, _, _, _) = place.slot {
                let shape = BookShapes.shape(of: work)

                hasher.combine(shape.cover)
                hasher.combine(shape.length)
            }
        }
    }

    /// Every face this shelf shows as a cover, at the size it shows it, for whoever prints them before
    /// the shelf comes into view.
    static func faces(in contents: Contents, isDark: Bool) -> [CoverPrint.Order] {
        let slot = slotHeight(contents)

        return places(contents).compactMap { place in
            guard
                case let .book(work, _, _, _) = place.slot,
                let url = work.coverURL,
                standsAsCover(place.slot, in: contents)
            else { return nil }

            let size = CGSize(width: contents.coverWidth, height: standing(place.slot, in: contents, slot: slot))

            return CoverPrint.Order(url: url, size: size, isDark: isDark)
        }
    }

    /// Every cover this shelf will show, for whoever pulls them off the disk before it does.
    static func covers(in contents: Contents) -> [URL] {
        places(contents).compactMap { place in
            guard case let .book(work, _, _, _) = place.slot else { return nil }

            return work.coverURL
        }
    }

    // MARK: - What stands where

    private static func layout(_ contents: Contents, places: [Place], across available: CGFloat) -> ShelfLayout {
        let slot = slotHeight(contents)
        let tiles = places.map { place in
            ShelfLayout.Tile(
                id: place.id,
                run: place.run,
                width: width(of: place.slot, in: contents),
                height: standing(place.slot, in: contents, slot: slot)
            )
        }

        return ShelfLayout(tiles: tiles, slot: slot, across: available, gutter: Shelf.gutter)
    }

    private static func places(_ contents: Contents) -> [Place] {
        let held = contents.runs.flatMap { run in run.slots.map { Place(slot: $0, run: run.id) } }

        return held + contents.alone.map { Place(slot: $0, run: nil) }
    }

    /// The tallest cover on this shelf, which is the slot every book on it stands in.
    private static func slotHeight(_ contents: Contents) -> CGFloat {
        let shapes = (contents.runs.flatMap(\.slots) + contents.alone).compactMap { slot -> CGFloat? in
            guard case let .book(work, _, _, _) = slot else { return nil }

            return BookShapes.shape(of: work).cover
        }

        return Design.Size.coverHeight(width: contents.coverWidth, ratio: shapes.max() ?? Shelf.unknownShape)
    }

    private static func standsAsCover(_ slot: SeriesSlot, in contents: Contents) -> Bool {
        guard case let .book(_, _, _, isShelved) = slot else { return contents.showsEveryCover }

        return contents.showsEveryCover || !isShelved
    }

    private static func width(of slot: SeriesSlot, in contents: Contents) -> CGFloat {
        guard
            case let .book(work, _, _, _) = slot
        else {
            return contents.showsEveryCover ? contents.coverWidth : Design.Size.spine
        }

        return standsAsCover(slot, in: contents)
            ? contents.coverWidth
            : Shelf.spineWidth(share: BookShapes.shape(of: work).length, cover: contents.coverWidth)
    }

    /// How tall a book stands, which is how tall its own cover comes out. A shelf whose books are all
    /// one height is a shelf of one book printed over and over.
    private static func standing(_ slot: SeriesSlot, in contents: Contents, slot height: CGFloat) -> CGFloat {
        guard case let .book(work, _, _, _) = slot, let shape = BookShapes.shape(of: work).cover else { return height }

        return Design.Size.coverHeight(width: contents.coverWidth, ratio: shape)
    }

    // MARK: - Building

    /// A view for everything on the shelf, and nothing left over for what has gone from it.
    private func build(_ contents: Contents) {
        var wanted: Set<String> = []

        for place in places {
            wanted.insert(place.id)

            make(place, in: contents)
        }

        var held: Set<String> = []

        for bracket in layout.brackets {
            held.insert(bracket.id)
            self.bracket(bracket, in: contents)
        }

        discard(&books, keeping: wanted)
        discard(&brackets, keeping: held)
    }

    private func discard<View: UIView>(_ views: inout [String: View], keeping wanted: Set<String>) {
        for (id, view) in views where !wanted.contains(id) {
            view.removeFromSuperview()
            views[id] = nil

            guard let book = view as? BookView else { continue }

            book.stopLoading()

            if Self.spare.count < Self.spares { Self.spare.append(book) }
        }
    }

    /// How many books to keep back: enough for the few cards on screen to be emptied into and filled
    /// from.
    private static let spares = 200

    /// Makes books ahead of the first scroll, a handful between frames, so a card coming into view
    /// dresses books it already has rather than making them in the middle of a frame.
    static func prepare(upTo count: Int) {
        guard spare.count < min(count, spares) else { return }

        DispatchQueue.main.async {
            for _ in 0 ..< preparedAtOnce where spare.count < min(count, spares) { spare.append(BookView()) }

            prepare(upTo: count)
        }
    }

    /// How many books are made between two frames while the shelf prepares.
    private static let preparedAtOnce = 6

    /// A view for one place on the shelf, whichever kind of place it is.
    private func make(_ place: Place, in contents: Contents) {
        let view: BookView
        var isNew = false

        if let held = books[place.id] {
            view = held
        } else {
            view = Self.spare.popLast() ?? BookView()
            books[place.id] = view
            addSubview(view)
            isNew = true
        }

        // Told again every time rather than only when the view is made: a place holds the book as it
        // was, so a view keeping its first closures opens and offers yesterday's copy of it.
        view.onTap = { [weak self] in self?.tapped(at: place) }
        view.menu = { [weak self] in self?.menu(at: place) }

        let slot = Self.slotHeight(contents)

        view.show(BookView.Contents(
            stands: Self.stands(place.slot, in: contents),
            edge: Self.edgeWidth(of: place.slot, in: contents),
            face: contents.coverWidth,
            standing: Self.standing(place.slot, in: contents, slot: slot),
            box: slot
        ))

        if isNew { view.turned = Self.standsAsCover(place.slot, in: contents) ? 1 : 0 }
    }

    private static func stands(_ slot: SeriesSlot, in contents: Contents) -> BookView.Contents.Stands {
        switch slot {
            case let .book(work, number, title, _):
                .book(work, number: number, title: title, marks: CoverView.Marks(reading: ReadingMark(work)))
            case let .missing(number):
                .gap(number)
        }
    }

    /// How thick this place stands. A volume the reader doesn't hold has no length to be measured by,
    /// so it takes the thinnest a book may be.
    private static func edgeWidth(of slot: SeriesSlot, in contents: Contents) -> CGFloat {
        guard case let .book(work, _, _, _) = slot else { return Design.Size.spine }

        return Shelf.spineWidth(share: BookShapes.shape(of: work).length, cover: contents.coverWidth)
    }

    /// A tap on a cover opens the book; a tap on a spine, or on a volume that isn't there, turns the
    /// whole run round.
    private func tapped(at place: Place) {
        guard
            let contents,
            case let .book(work, _, _, _) = place.slot,
            Self.standsAsCover(place.slot, in: contents)
        else {
            onToggle?()
            return
        }
        guard books[place.id] != nil else { return }

        onOpen?(work) { [weak self] zoom in self?.books[place.id]?.face(during: zoom) }
    }

    private func menu(at place: Place) -> UIMenu? {
        guard case let .book(work, _, _, _) = place.slot else { return nil }

        return bookMenu?(work)
    }

    private func bracket(_ bracket: ShelfLayout.Bracket, in contents: Contents) {
        let view: BracketView

        if let held = brackets[bracket.id] {
            view = held
        } else {
            view = BracketView()
            view.onMenu = { [weak self] in self?.runMenu?(bracket.run) }
            brackets[bracket.id] = view
            // Behind the books but on the bookcase: a turning book stands past its own slot, and the line
            // under the run it belongs to is a mark on the plank rather than laid over the books on it.
            insertSubview(view, aboveSubview: bookcase)
        }

        view.show(
            title: contents.runs.first { $0.id == bracket.run }?.title ?? "",
            opens: bracket.opens,
            closes: bracket.closes
        )
    }

    /// Every view where the layout says it stands, at this point in the turn. A book takes the whole
    /// slot it stands in, since the turn is worked out against the middle of that slot rather than the
    /// middle of the book.
    ///
    /// Everything is read off the clock here rather than handed to an animator, so a layout in the
    /// middle of a turn puts the books where the turn has got to instead of where it is going.
    private func stand() {
        guard let contents else { return }

        let reached = progress
        let slot = Self.slotHeight(contents)

        for place in places {
            let target: CGFloat = Self.standsAsCover(place.slot, in: contents) ? 1 : 0
            let from = turning?.from[place.id] ?? target

            books[place.id]?.turned = from + (target - from) * reached
        }

        for placed in layout.placed {
            let box = CGRect(
                x: Self.inset + placed.frame.minX,
                y: placed.frame.maxY - slot,
                width: placed.frame.width,
                height: slot
            )
            let frame = turning?.was[placed.id].map { $0.carried(to: box, at: reached) } ?? box

            books[placed.id]?.frame = frame
        }

        for bracket in layout.brackets {
            let was = turning?.was[bracket.id]
            let frame = bracket.frame.offsetBy(dx: Self.inset, dy: 0)

            brackets[bracket.id]?.frame = was.map { $0.carried(to: frame, at: reached) } ?? frame
        }

        // As deep as the shelf stands at this point in the turn, which is what the rows are drawn down.
        bookcase.frame = bounds
    }
}

private extension CGRect {
    /// This rectangle on its way to another one.
    func carried(to other: CGRect, at part: CGFloat) -> CGRect {
        CGRect(
            x: minX + (other.minX - minX) * part,
            y: minY + (other.minY - minY) * part,
            width: width + (other.width - width) * part,
            height: height + (other.height - height) * part
        )
    }
}
