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
        var progress: Double?
        var isComplete = false
        var origin: CoverOrigin?
        var isOngoing = false
        /// Which volume of its series this is, carried on the face as well as on the spine so the
        /// figure stays put as the book turns rather than going out with the spine.
        var volume: Int?
        /// Which way the book's own colour runs, which is what its plate is set in.
        var isDark = false

        func with(volume: Int?, isDark: Bool) -> Marks {
            var marks = self

            marks.volume = volume
            marks.isDark = isDark

            return marks
        }
    }

    private let artwork = UIImageView()
    private let placeholder = UIImageView()
    private let hinge = CAGradientLayer()
    private let edge = CAShapeLayer()
    private let board = CAShapeLayer()
    private let progress = UIImageView()
    private let source = UIImageView()
    private let ongoing = UIImageView()
    private let volume = UIImageView()

    private var marks = Marks()
    private var loading: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)

        layer.mask = board
        backgroundColor = UIColor(Design.Surface.fill)

        // Filled rather than fitted: the box a shelf gives a book is worked out from that book's own
        // cover and rounded to whole points, and a picture fitted into a box a fraction of a point off
        // its shape leaves a bar of nothing down the side it is bound on.
        artwork.contentMode = .scaleAspectFill
        placeholder.contentMode = .center
        placeholder.image = UIImage(systemName: "book.closed")

        for view in [ artwork, placeholder, progress, source, ongoing, volume ] { addSubview(view) }

        // A layer of its own rather than this view's border, which draws over every sublayer it has:
        // the hinge is the board bending, and a hairline of the card's own colour laid over it is the
        // white line a cover used to carry down the side it is bound on.
        edge.lineWidth = Design.Stroke.hairline
        edge.fillColor = nil
        layer.insertSublayer(edge, above: placeholder.layer)

        // Over the picture and over that edge: it is the board itself, not something laid on it.
        layer.insertSublayer(hinge, above: edge)
        hinge.startPoint = CGPoint(x: 0, y: 0.5)
        hinge.endPoint = CGPoint(x: 1, y: 0.5)

        registerForTraitChanges([ UITraitUserInterfaceStyle.self ]) { (self: Self, _) in self.paint() }
        paint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// What this cover is of, from the book's own artwork down to the marks over it.
    func show(_ work: Book, marks: Marks) {
        self.marks = marks
        loading?.cancel()

        let held = work.coverURL.flatMap(CoverImages.image(for:))

        artwork.image = held
        placeholder.isHidden = held != nil

        if let url = work.coverURL, held == nil {
            loading = Task { [weak self] in
                guard let loaded = await CoverCache.shared.image(for: url) else { return }

                CoverImages.remember(loaded, for: url)

                guard !Task.isCancelled, self?.window != nil else { return }

                self?.artwork.image = loaded
                self?.placeholder.isHidden = true
                self?.onArtwork?()
            }
        }

        paint()
        setNeedsLayout()
    }

    /// Told when the picture finally arrives, since a spine printed without it has to be printed again.
    var onArtwork: (() -> Void)?

    func stopLoading() {
        loading?.cancel()
        loading = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        artwork.frame = bounds
        placeholder.frame = bounds
        placeholder.preferredSymbolConfiguration = .init(pointSize: bounds.width * 0.3)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hinge.frame = bounds
        edge.frame = bounds
        board.frame = bounds
        edge.path = Self.board(in: bounds)
        board.path = edge.path
        crease()
        CATransaction.commit()

        let inset = Design.Space.extraSmall
        let mark = Design.Size.mark

        progress.frame = CGRect(x: bounds.maxX - inset - mark, y: bounds.maxY - inset - mark, width: mark, height: mark)
        source.frame = CGRect(x: inset, y: inset, width: mark, height: mark)
        ongoing.frame = CGRect(x: inset, y: bounds.maxY - inset - mark, width: mark, height: mark)

        // Along the foot, in the middle: the corners are spoken for, and a volume standing under the
        // artwork reads as part of the book rather than as another mark laid on it.
        volume.sizeToFit()
        volume.frame.origin = CGPoint(
            x: bounds.midX - volume.frame.width / 2,
            y: bounds.maxY - inset - volume.frame.height
        )
    }

    /// The shape of a board: square along the edge it is bound on and rounded at the two corners that
    /// are handled, which is how a book is cut.
    static func board(in rect: CGRect) -> CGPath {
        let bound = Design.Radius.cover
        let outer = Design.Radius.foreEdge
        let path = CGMutablePath()

        path.move(to: CGPoint(x: rect.minX + bound, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.maxY),
            radius: outer
        )
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX, y: rect.maxY),
            radius: outer
        )
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX, y: rect.minY),
            radius: bound
        )
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.minY),
            radius: bound
        )
        path.closeSubpath()

        return path
    }

    /// The crease this cover is bound along, laid out across whatever width it has been given.
    private func crease() {
        guard bounds.width > 0 else { return }

        let scheme: ColorScheme = traitCollection.userInterfaceStyle == .dark ? .dark : .light
        let stops = Board.crease(scheme)

        hinge.colors = stops.map { UIColor($0.colour).resolvedColor(with: traitCollection).cgColor }
        hinge.locations = stops.map { NSNumber(value: min(1, $0.at / bounds.width)) }
    }

    /// Every colour this view holds itself, since a layer keeps the colour it was given rather than
    /// following the shelf into the dark.
    private func paint() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        let scheme =
            isDark ? UITraitCollection(userInterfaceStyle: .dark) : UITraitCollection(userInterfaceStyle: .light)

        edge.strokeColor = UIColor(Design.Surface.edge).resolvedColor(with: scheme).cgColor
        placeholder.tintColor = UIColor.tertiaryLabel
        crease()

        if let read = marks.progress, read > 0 {
            progress.image = MarkPrint.progress(read, isComplete: marks.isComplete, isDark: isDark)
            progress.isHidden = false
        } else {
            progress.isHidden = true
        }

        if let origin = marks.origin {
            source.image = MarkPrint.circle(
                origin.systemImage,
                tint: UIColor(Design.Palette.neutral).resolvedColor(with: scheme),
                isDark: isDark
            )
            source.isHidden = false
        } else {
            source.isHidden = true
        }

        ongoing.isHidden = !marks.isOngoing
        ongoing.image = MarkPrint.circle(
            "pencil",
            tint: UIColor(Design.Palette.neutral).resolvedColor(with: scheme),
            isDark: isDark
        )

        if let number = marks.volume {
            volume.image = SpinePrint.plate(number, isDark: marks.isDark)
            volume.isHidden = false
        } else {
            volume.isHidden = true
        }
    }
}
