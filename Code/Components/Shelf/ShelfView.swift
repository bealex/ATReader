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
        /// Whether a book is picked out, while the shelf is picking books. Nothing while it isn't.
        let isPicked: ((Book) -> Bool)?
        /// Where a book came from, which the shelf is told rather than working out.
        let origin: (Int) -> CoverOrigin?
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
    /// A book being opened, and where its face stands on the screen as it is.
    var onOpen: ((Book, CGRect) -> Void)?
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

    /// How far round each book on the shelf stands, which is what a turn moves.
    var turns: [String: CGFloat] { books.mapValues(\.turned) }

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
        layout = Self.layout(contents, places: places, across: bounds.width)
        build(contents)

        turning = Turning(started: CACurrentMediaTime(), from: from, was: was, wasHeight: wasHeight)
        link?.invalidate()
        link = CADisplayLink(target: self, selector: #selector(stepped))
        link?.add(to: .main, forMode: .common)
        stand()
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

        layout = Self.layout(contents, places: places, across: bounds.width)
        build(contents)
        stand()
    }

    /// How tall this shelf comes out, before any of it is built.
    static func height(_ contents: Contents, across available: CGFloat) -> CGFloat {
        layout(contents, places: places(contents), across: available).height
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

            return work.coverURL.flatMap(CoverShapes.aspect(for:))
        }

        return Design.Size.coverHeight(width: contents.coverWidth, ratio: shapes.max() ?? Shelf.unknownShape)
    }

    private static func standsAsCover(_ slot: SeriesSlot, in contents: Contents) -> Bool {
        guard case let .book(_, _, _, isRead) = slot else { return contents.showsEveryCover }

        return contents.showsEveryCover || !isRead
    }

    private static func width(of slot: SeriesSlot, in contents: Contents) -> CGFloat {
        guard
            case let .book(work, _, _, _) = slot
        else {
            return contents.showsEveryCover ? contents.coverWidth : Design.Size.spine
        }

        return standsAsCover(slot, in: contents)
            ? contents.coverWidth
            : Shelf.spineWidth(of: work, cover: contents.coverWidth)
    }

    /// How tall a book stands, which is how tall its own cover comes out. A shelf whose books are all
    /// one height is a shelf of one book printed over and over.
    private static func standing(_ slot: SeriesSlot, in contents: Contents, slot height: CGFloat) -> CGFloat {
        guard
            case let .book(work, _, _, _) = slot,
            let shape = work.coverURL.flatMap(CoverShapes.aspect(for:))
        else { return height }

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
            (view as? BookView)?.stopLoading()
            view.removeFromSuperview()
            views[id] = nil
        }
    }

    /// A view for one place on the shelf, whichever kind of place it is.
    private func make(_ place: Place, in contents: Contents) {
        let view: BookView
        var isNew = false

        if let held = books[place.id] {
            view = held
        } else {
            view = BookView()
            view.onTap = { [weak self] in self?.tapped(at: place) }
            view.menu = { [weak self] in self?.menu(at: place) }
            books[place.id] = view
            addSubview(view)
            isNew = true
        }

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
                .book(
                    work,
                    number: number,
                    title: title,
                    marks: CoverView.Marks(
                        progress: work.readingProgress,
                        isComplete: (work.readingProgress ?? 0) >= Book.readThreshold,
                        origin: contents.origin(work.id),
                        isOngoing: work.isOngoing,
                        isPicked: contents.isPicked.map { $0(work) }
                    )
                )
            case let .missing(number):
                .gap(number)
        }
    }

    /// How thick this place stands. A volume the reader doesn't hold has no length to be measured by,
    /// so it takes the thinnest a book may be.
    private static func edgeWidth(of slot: SeriesSlot, in contents: Contents) -> CGFloat {
        guard case let .book(work, _, _, _) = slot else { return Design.Size.spine }

        return Shelf.spineWidth(of: work, cover: contents.coverWidth)
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

        onOpen?(work, books[place.id]?.faceOnScreen ?? .zero)
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
            // Behind the books: a turning book stands past its own slot, and the line under the run it
            // belongs to is a mark on the shelf rather than something laid over the books on it.
            insertSubview(view, at: 0)
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
            let box = CGRect(x: placed.frame.minX, y: placed.frame.maxY - slot, width: placed.frame.width, height: slot)
            let frame = turning?.was[placed.id].map { $0.carried(to: box, at: reached) } ?? box

            books[placed.id]?.frame = frame
        }

        for bracket in layout.brackets {
            let was = turning?.was[bracket.id]

            brackets[bracket.id]?.frame = was.map { $0.carried(to: bracket.frame, at: reached) } ?? bracket.frame
        }
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
