//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import DesignSystem
import SwiftUI
import UIKit

/// A book's face: its artwork, the board bending into its binding, and the few marks a shelf puts on it.
final class CoverView: UIView {
    /// What a cover shows besides the picture.
    struct Marks {
        var reading: ReadingMark?
    }

    /// The printed face, or the bare board standing in for it until the face arrives.
    private let face = UIImageView()
    /// What a book with no cover at all shows, and the marks over a face, each made the first time a
    /// book needs it: a card coming into view makes every book on it, and most need none of these.
    private var placeholder: UIImageView?
    /// The figure or glyph on the bookmark. The ribbon under it is part of the line's own shape.
    private var figure: UIImageView?
    /// The line read and the line of shade under it, cut to the board's shape the way everything else
    /// printed on a cover is.
    private var line: CAShapeLayer?
    private var lineShade: CAShapeLayer?
    /// The crease, laid again over everything drawn on the board after the face was printed.
    private var binding: CALayer?

    private var marks = Marks()
    private var url: URL?
    /// The face hanging now, where it is a printed one rather than the bare board.
    private var shown: CoverPrint.Order?
    private var loading: (order: CoverPrint.Order, task: Task<Void, Never>)?

    /// Whether the face can be seen. A book standing on its edge has no use for its cover's picture, so
    /// nothing is decoded or drawn for it until it turns.
    var wantsArtwork = false {
        didSet {
            guard wantsArtwork != oldValue else { return }

            refreshFace()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        face.contentMode = .scaleToFill
        addSubview(face)

        registerForTraitChanges([ UITraitUserInterfaceStyle.self ]) { (self: Self, _) in
            self.paint()
            self.refreshFace()
        }
        paint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// What this cover is of, from the book's own artwork down to the marks over it.
    func show(_ work: Book, marks: Marks) {
        self.marks = marks

        if url != work.coverURL {
            url = work.coverURL
            stopLoading()
        }

        if url == nil {
            let placeholder = made(&placeholder)

            placeholder.contentMode = .center
            placeholder.image = UIImage(systemName: "book.closed")
            placeholder.isHidden = false
        } else {
            placeholder?.isHidden = true
        }

        paint()
        refreshFace()
    }

    /// One of the views a book makes only when it needs it, made now if it hasn't been.
    private func made(_ view: inout UIImageView?) -> UIImageView {
        if let view { return view }

        let new = UIImageView()

        addSubview(new)
        view = new
        setNeedsLayout()

        return new
    }

    /// Told when the picture finally arrives, since a spine printed without it has to be printed again.
    var onArtwork: (() -> Void)?

    /// Gives up the face on its way, for a book that has left the screen.
    func stopLoading() {
        loading?.task.cancel()
        loading = nil
    }

    /// Asks again for a face given up while the book was off the screen.
    func resumeLoading() { refreshFace() }

    override func layoutSubviews() {
        super.layoutSubviews()

        face.frame = bounds
        placeholder?.frame = bounds
        placeholder?.preferredSymbolConfiguration = .init(pointSize: bounds.width * 0.3)

        placeReading()

        refreshFace()
    }

    /// Hangs the printed face where it is at hand, and otherwise the bare board, printing the face in
    /// the background and fading it in once it is.
    private func refreshFace() {
        let isDark = traitCollection.userInterfaceStyle == .dark

        guard
            let url,
            bounds.width > 0,
            bounds.height > 0
        else {
            stopLoading()
            shown = nil
            face.image = CoverPrint.blank(isDark: isDark)
            return
        }

        let order = CoverPrint.Order(url: url, size: bounds.size, isDark: isDark)

        guard shown != order else { return }

        if let held = CoverPrint.held(order) {
            stopLoading()
            face.image = held
            shown = order
            return
        }

        // Another book's face never stands in for this one; this book's own at another size can.
        if shown?.url != url || shown?.isDark != isDark {
            face.image = CoverPrint.blank(isDark: isDark)
            shown = nil
        }

        guard wantsArtwork else { return stopLoading() }
        guard loading?.order != order else { return }

        stopLoading()
        loading = (
            order,
            Task { [weak self] in
                guard let printed = await CoverPrint.printed(order) else { return }
                guard let self, !Task.isCancelled, self.loading?.order == order else { return }

                self.loading = nil
                self.shown = order
                self.face.arrive(printed)
                self.onArtwork?()
            }
        )
    }

    /// The line along the top edge and the bookmark at its end. The line runs from the cover's own edge
    /// and is cut with the board, so it rounds where the board rounds.
    private func placeReading() {
        guard let reading = marks.reading, bounds.width > 0 else { return }

        // Layers of its own rather than a view's: a path set on one animates unless it is told not to.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let board = CoverPrint.board(in: bounds)
        let silhouette = BookmarkMark.silhouette(reached: reading.reached, across: bounds.width)
        let shade = Design.Stroke.readingShade

        line?.path = board.intersection(silhouette)
        // The stroke as a shape of its own, so it can be cut with the board as everything else is. The
        // half of it that falls inside the line is covered by the line itself.
        lineShade?.path = board.intersection(
            silhouette.copy(strokingWithWidth: shade * 2, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
        )
        figure?.frame = CGRect(
            x: BookmarkMark.offset(reached: reading.reached, across: bounds.width),
            y: 0,
            width: Design.Size.bookmark,
            height: Design.Size.bookmarkHeight
        )
        binding?.frame = CGRect(x: 0, y: 0, width: CoverPrint.bindingWidth, height: BookmarkMark.depth)
    }

    /// The marks over the face, which take the room's colours rather than the book's.
    private func paint() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        let scheme =
            isDark ? UITraitCollection(userInterfaceStyle: .dark) : UITraitCollection(userInterfaceStyle: .light)
        placeholder?.tintColor = UIColor.tertiaryLabel

        if let reading = marks.reading {
            let figure = made(&figure)
            let line = madeLayer(&line) { CAShapeLayer() }
            let shade = madeLayer(&lineShade) { CAShapeLayer() }
            let crease = madeLayer(&binding) { CALayer() }
            let print = CoverPrint.binding(isDark: isDark)

            figure.image = MarkPrint.face(reading.face)
            figure.isHidden = false
            line.fillColor = UIColor(reading.tint).resolvedColor(with: scheme).cgColor
            line.isHidden = false
            shade.fillColor = UIColor(BookmarkMark.shade).cgColor
            shade.isHidden = false
            crease.contents = print.cgImage
            crease.contentsScale = print.scale
            crease.isHidden = false

            // The shade under the line, the figure on the ribbon, and the crease over all of it.
            layer.insertSublayer(line, above: shade)
            bringSubviewToFront(figure)
            layer.insertSublayer(crease, above: figure.layer)
            placeReading()
        } else {
            figure?.isHidden = true
            line?.isHidden = true
            lineShade?.isHidden = true
            binding?.isHidden = true
        }
    }

    /// One of the layers a cover makes only when it needs it, made now if it hasn't been.
    private func madeLayer<Held: CALayer>(_ held: inout Held?, _ make: () -> Held) -> Held {
        if let held { return held }

        let made = make()

        layer.addSublayer(made)
        held = made
        setNeedsLayout()

        return made
    }
}
