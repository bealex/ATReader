//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import DesignSystem
import UIKit

/// A book on a shelf, turning between the edge it stands on and the face it is taken down for.
///
/// The two panels are hinged along the spine's outer edge and projected from one eye, which `Hinge`
/// works out. Every frame of the turn is worked out from the number itself, since halfway between two
/// projections is not the projection of half a turn.
final class BookView: UIView {
    /// Everything about one place on the shelf this view has to be told.
    struct Contents {
        let stands: Stands
        /// How thick this book is, how wide its cover comes out, and how tall it stands.
        let edge: CGFloat
        let face: CGFloat
        let standing: CGFloat
        /// The slot it stands in, which is as tall as the tallest book beside it.
        let box: CGFloat

        /// What is in this place: a book the reader holds, or a volume they don't.
        ///
        /// A volume they don't hold turns with the run it belongs to rather than sitting still while
        /// the books either side of it move: it is one of the run, and a gap that held still would
        /// read as a hole in the shelf instead.
        enum Stands {
            case book(Book, number: Int?, title: String, marks: CoverView.Marks)
            case gap(Int)
        }
    }

    private let edgePanel = UIView()
    private let facePanel = UIView()
    private let spine = UIImageView()
    private let cover = CoverView()
    private let edgeGap = GapView(frame: .zero)
    private let faceGap = GapView(frame: .zero)
    private let edgeShade = UIView()
    private let faceShade = UIView()

    private var contents: Contents?
    private var held: CGFloat = 0
    private var printing: Task<Void, Never>?
    /// Which book the spine now hanging is of, so a view given a different one clears it first.
    private var shown: Int?

    var onTap: (() -> Void)?
    var menu: (() -> UIMenu?)?

    /// The board this book's artwork is on, which a zoom into it grows out of.
    var face: UIView { facePanel }

    override init(frame: CGRect) {
        super.init(frame: frame)

        for panel in [ edgePanel, facePanel ] {
            panel.layer.anchorPoint = .zero
            // A layer standing at an angle is clipped to whole pixels unless it is told otherwise, and
            // a book is at an angle for the whole of its turn: without this both panels come out with
            // a stepped edge, and the joint between them a hair of nothing.
            panel.layer.allowsEdgeAntialiasing = true
            panel.isUserInteractionEnabled = false
            addSubview(panel)
        }

        edgePanel.addSubview(spine)
        facePanel.addSubview(cover)
        edgePanel.addSubview(edgeGap)
        facePanel.addSubview(faceGap)
        edgeGap.side = .edge
        faceGap.side = .face

        for content in [ spine, cover, edgeGap, faceGap ] { content.layer.allowsEdgeAntialiasing = true }

        for shade in [ edgeShade, faceShade ] {
            shade.backgroundColor = .black
            shade.isUserInteractionEnabled = false
            shade.alpha = 0
        }

        edgePanel.addSubview(edgeShade)
        facePanel.addSubview(faceShade)

        cover.onArtwork = { [weak self] in self?.reprint() }

        isAccessibilityElement = true
        accessibilityTraits = .button
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        addInteraction(UIContextMenuInteraction(delegate: self))
        registerForTraitChanges([ UITraitUserInterfaceStyle.self ]) { (self: Self, _) in self.reprint() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// What stands here, and how. Told again for the same one, it keeps its turn.
    func show(_ contents: Contents) {
        self.contents = contents

        switch contents.stands {
            case let .book(work, _, _, marks):
                // Printed first: what a cover's own plate is set in is what its spine turned out to be.
                reprint()
                cover.show(work, marks: marks.with(volume: volume, isDark: isDark(of: work)))
            case let .gap(number):
                edgeGap.number = number
                faceGap.number = number
        }

        for content in [ spine, cover ] { content.isHidden = !isBook }

        for content in [ edgeGap, faceGap ] { content.isHidden = isBook }

        setNeedsLayout()
        layoutIfNeeded()
        place(held)
    }

    /// The volume this place carries, whether a book stands in it or not.
    private var volume: Int? {
        switch contents?.stands {
            case let .book(_, number, _, _): number
            case let .gap(number): number
            case nil: nil
        }
    }

    private var isBook: Bool {
        guard case .book = contents?.stands else { return false }

        return true
    }

    /// Which way a book's own colour runs, so its cover's plate is set in what its spine was printed in.
    private func isDark(of work: Book) -> Bool {
        SpinePrint.isDark(of: work.id) ?? (traitCollection.userInterfaceStyle == .dark)
    }

    func stopLoading() {
        cover.stopLoading()
        printing?.cancel()
        printing = nil
    }

    /// Turns the book, either at once or over the time a hinge takes.
    /// How far round this book has turned, which whatever is animating it sets every frame.
    var turned: CGFloat {
        get { held }
        set {
            held = newValue
            place(newValue)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard let contents else { return }

        let top = bounds.height - contents.standing

        stand(edgePanel, at: CGPoint(x: 0, y: top), size: CGSize(width: contents.edge, height: contents.standing))
        stand(facePanel, at: CGPoint(x: 0, y: top), size: CGSize(width: contents.face, height: contents.standing))
        spine.frame = edgePanel.bounds
        cover.frame = facePanel.bounds
        edgeGap.frame = edgePanel.bounds
        faceGap.frame = facePanel.bounds
        edgeShade.frame = edgePanel.bounds
        faceShade.frame = facePanel.bounds
        place(held)
    }

    /// A panel stands by its own top left, since that is the corner the turn holds still and a frame
    /// means nothing once a transform is on it.
    private func stand(_ panel: UIView, at origin: CGPoint, size: CGSize) {
        panel.layer.bounds = CGRect(origin: .zero, size: size)
        panel.layer.position = origin
    }

    /// Where the two panels stand at this point in the turn, and how far each has turned out of the
    /// light. Both are worked out here rather than animated, because neither can be interpolated.
    private func place(_ turned: CGFloat) {
        guard let contents else { return }

        let hinge = Hinge(edge: contents.edge, face: contents.face, turned: turned)
        // The eye is level with the middle of the slot, which is above the middle of a short book, so
        // every book on the shelf leans towards the same line.
        let eye = contents.standing - contents.box / 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for (panel, which, shade) in [
            (edgePanel, Hinge.Panel.edge, edgeShade),
            (facePanel, Hinge.Panel.face, faceShade),
        ] {
            let light = hinge.light(of: which)

            panel.layer.transform = hinge.transform(of: which, eye: eye)
            shade.alpha = Hinge.shading * (1 - light)
            // A panel edge-on to the reader is not drawn at all: standing both behind every book
            // would draw the shelf twice over and show one of them.
            panel.isHidden = light <= 0
        }

        CATransaction.commit()
    }

    /// The spine is a picture, so it is hung again whenever what it is a picture of changes, and asked
    /// of the press when the one wanted has not been printed yet.
    private func reprint() {
        guard
            let contents,
            case let .book(work, number, title, _) = contents.stands,
            contents.edge > 0,
            contents.standing > 0
        else { return }

        let size = CGSize(width: contents.edge, height: contents.standing)
        let isDark = traitCollection.userInterfaceStyle == .dark
        let standing = SpinePrint.standing(of: work, number: number, title: title, size: size, isDark: isDark)

        printing?.cancel()
        printing = nil

        // Whatever is filed, but never the book that stood here before this one.
        if standing.image != nil || shown != work.id { spine.image = standing.image }

        shown = work.id

        guard !standing.isWanted else { return }

        printing = Task { [weak self] in
            let pulled = await SpinePress.printed(of: work, number: number, title: title, size: size, isDark: isDark)

            guard let pulled, !Task.isCancelled else { return }

            self?.spine.image = pulled
        }
    }

    /// What a reader who cannot see the shelf is told, which is what this place is showing: a book
    /// standing on its edge says it has been read, and one taken down names itself.
    override var accessibilityLabel: String? {
        get {
            switch contents?.stands {
                case let .book(work, number, _, _):
                    guard held < Hinge.facing else { return work.title }

                    return number.map { String(localized: "Volume \($0), \(work.title), read") }
                        ?? String(localized: "\(work.title), read")
                case let .gap(number):
                    return String(localized: "Volume \(number), not in your library")
                case nil:
                    return nil
            }
        }
        set {}
    }

    override var accessibilityHint: String? {
        get {
            guard case .book = contents?.stands, held >= Hinge.facing else { return nil }

            return String(localized: "Opens the book")
        }
        set {}
    }

    @objc
    private func tapped() { onTap?() }
}

extension BookView: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let menu = menu?() else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menu }
    }
}
