//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import DesignSystem
import UIKit

/// A book between its cover and its first page, drawn at any point of being opened.
///
/// The book grows in one sweep from where its cover stands to the whole screen, and its cover swings open
/// about the spine as it sets off, bending as a thin board does. The page under it is the screen being
/// opened, live, scaled to fit the book.
@MainActor
final class OpeningBook {
    private let page: UIView
    private let screen: CGRect
    private let cover: CGRect?
    private let picture: CGImage?

    /// The page's paper, as large as the book: it letterboxes the page and hides whatever is under a
    /// screen that is only opaque once it has arrived.
    private let sheet = UIView()
    private let over = UIView()
    private let crease = CAGradientLayer()
    private var strips: [(board: CALayer, shade: CALayer)] = []
    private let inside: CGColor

    /// Lays the book out over `page`, which is already in `container` at its full size.
    ///
    /// - Parameters:
    ///   - cover: where the cover stands, in the container's space; without it the page only fades in.
    ///   - picture: the cover as drawn there; without one the page grows out of `cover` with nothing over it.
    ///   - paper: the colour of the page.
    init(page: UIView, in container: UIView, cover: CGRect?, picture: UIImage?, paper: UIColor) {
        self.page = page
        self.screen = container.bounds
        self.cover = cover
        self.picture = picture?.cgImage
        inside = UIColor.secondarySystemBackground.resolvedColor(with: container.traitCollection).cgColor

        sheet.isUserInteractionEnabled = false
        sheet.backgroundColor = paper
        sheet.layer.maskedCorners = [ .layerMaxXMinYCorner, .layerMaxXMaxYCorner ]
        sheet.layer.shadowColor = UIColor.black.cgColor
        sheet.layer.shadowRadius = Self.shadowRadius
        sheet.layer.shadowOffset = CGSize(width: 0, height: Self.shadowRadius / 2)
        container.insertSubview(sheet, belowSubview: page)

        over.isUserInteractionEnabled = false
        over.frame = screen
        container.insertSubview(over, aboveSubview: page)

        crease.startPoint = CGPoint(x: 0, y: 0.5)
        crease.endPoint = CGPoint(x: 1, y: 0.5)
        crease.colors = [ UIColor.black.cgColor, UIColor.clear.cgColor ]
        crease.isHidden = picture == nil
        over.layer.addSublayer(crease)

        if self.picture != nil { strips = (0 ..< Self.stripCount).map { _ in Self.strip(in: over.layer) } }
    }

    /// Takes the book away, leaving the page standing on its own, or taking it too where the book shut.
    func remove(withPage: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Gone before it is put back to full size, or the next frame shows the whole page once more.
        if withPage { page.removeFromSuperview() }

        page.transform = .identity
        page.alpha = 1
        sheet.removeFromSuperview()
        over.removeFromSuperview()
        CATransaction.commit()
    }

    /// The book at `open`, from nought, shut where its cover stands, to one, the page filling the screen,
    /// moved `shift` off its own path.
    func draw(open: CGFloat, shift: CGVector = .zero) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard
            let cover
        else {
            sheet.alpha = open
            return page.alpha = open
        }

        let grown = Self.settle(open)
        // Lifted slowly off the page before it swings, and still settling gently at the far side.
        let opened = Self.ease(pow(min(max(open / Self.opening, 0), 1), Self.lifting))
        let size = Self.mix(cover, screen, by: grown).size
        let middle = middle(at: open)
        let spread = CGRect(
            x: middle.x + shift.dx - size.width / 2,
            y: middle.y + shift.dy - size.height / 2,
            width: size.width,
            height: size.height
        )

        place(page: spread, cornered: Design.Radius.foreEdge * (1 - grown))

        // Faded in as the book leaves the shelf, where it cast none.
        sheet.layer.shadowOpacity = Float(Self.shadowing * Self.ease(open / Self.leaving) * (1 - grown))

        crease.frame = CGRect(
            origin: spread.origin,
            size: CGSize(width: spread.width * Self.creaseWidth, height: spread.height)
        )
        crease.opacity = Float(Self.creaseShading * sin(opened * .pi))

        guard picture != nil else { return page.alpha = min(open / Self.opening, 1) }

        hang(Leaf(width: spread.width, turned: opened), over: spread)
    }

    /// The live page scaled to fit inside `rect`, on a sheet of its own paper that fills the rest.
    private func place(page rect: CGRect, cornered radius: CGFloat) {
        let scale = min(rect.width / screen.width, rect.height / screen.height)

        page.transform = CGAffineTransform(translationX: rect.midX - screen.midX, y: rect.midY - screen.midY)
            .scaledBy(x: scale, y: scale)

        sheet.frame = rect
        sheet.layer.cornerRadius = radius
        sheet.layer.shadowPath =
            UIBezierPath(
                roundedRect: sheet.bounds,
                byRoundingCorners: [ .topRight, .bottomRight ],
                cornerRadii: CGSize(width: radius, height: radius)
            ).cgPath
    }

    /// Hangs the cover from the spine of the book standing at `book`, one strip at a time, each seen from
    /// an eye straight in front of the book, as a book turning on the shelf is.
    private func hang(_ leaf: Leaf, over book: CGRect) {
        let eye = CGPoint(x: book.midX, y: book.midY)
        let fromEye = CGPoint(x: book.minX - eye.x, y: 0)
        let distance = book.width * Self.perspective
        let height = book.height
        let seam = Self.seam / max(leaf.width, 1)

        for (strip, layers) in zip(leaf.strips(strips.count), strips) {
            let isLast = strip.cut.upperBound >= 1
            let front = leaf.showsFront(of: strip, hinge: fromEye, distance: distance)

            layers.board.bounds = CGRect(x: 0, y: 0, width: strip.length + (isLast ? 0 : Self.seam), height: height)
            layers.board.position = eye
            layers.board.zPosition = strip.toward
            layers.board.transform = leaf.transform(of: strip, hinge: fromEye, distance: distance)
            layers.board.contents = front ? picture : nil
            layers.board.backgroundColor = front ? nil : inside
            layers.board.contentsRect = CGRect(
                x: strip.cut.lowerBound,
                y: 0,
                width: strip.cut.upperBound - strip.cut.lowerBound + (isLast ? 0 : seam),
                height: Self.wholeHeight
            )
            layers.shade.frame = layers.board.bounds
            layers.shade.opacity = Float(Hinge.shading * (1 - strip.light))
        }
    }

    private static func strip(in parent: CALayer) -> (board: CALayer, shade: CALayer) {
        let board = CALayer()
        let shade = CALayer()

        board.anchorPoint = CGPoint(x: 0, y: 0.5)
        board.allowsEdgeAntialiasing = true
        board.contentsGravity = .resize
        shade.backgroundColor = UIColor.black.cgColor
        board.addSublayer(shade)
        parent.addSublayer(board)

        return (board, shade)
    }

    private static func mix(_ from: CGRect, _ into: CGRect, by share: CGFloat) -> CGRect {
        CGRect(
            x: from.minX + (into.minX - from.minX) * share,
            y: from.minY + (into.minY - from.minY) * share,
            width: from.width + (into.width - from.width) * share,
            height: from.height + (into.height - from.height) * share
        )
    }

    /// Where the book's middle stands at `open`, before any finger moves it.
    ///
    /// Across it runs a little past where it is going and settles back. Down it dips below the straight
    /// line and rises back into place, so a book flies low whichever shelf it left.
    func middle(at open: CGFloat) -> CGPoint {
        guard let cover else { return CGPoint(x: screen.midX, y: screen.midY) }

        let along = Self.settle(open)
        let held = min(max(open, 0), 1)
        let dip = screen.height * Self.dipping * Self.dipShape * pow(held, 3) * pow(1 - held, 2)

        return CGPoint(
            x: cover.midX + (screen.midX - cover.midX) * Self.overshooting(open),
            y: cover.midY + (screen.midY - cover.midY) * along + dip
        )
    }

    /// How far a finger that has moved the book by `moved` from where it stood open has to shift it off
    /// its own path at `open`, for the book to stay under the finger.
    func shift(following moved: CGVector, at open: CGFloat) -> CGVector {
        let path = middle(at: open)

        return CGVector(dx: screen.midX + moved.dx - path.x, dy: screen.midY + moved.dy - path.y)
    }

    /// How open the book is when it has grown `grown` of the way to its full size.
    static func open(grown: CGFloat) -> CGFloat {
        let held = min(max(grown, 0), 1)
        var range: ClosedRange<CGFloat> = 0 ... 1

        // Halved until well under a point on any screen.
        for _ in 0 ..< 20 {
            let middle = (range.lowerBound + range.upperBound) / 2

            range = settle(middle) < held ? middle ... range.upperBound : range.lowerBound ... middle
        }

        return (range.lowerBound + range.upperBound) / 2
    }

    /// Nought to one, leaving and arriving with neither speed nor acceleration: smootherstep.
    private static func settle(_ share: CGFloat) -> CGFloat {
        let held = min(max(share, 0), 1)

        return held * held * held * (held * (held * 6 - 15) + 10)
    }

    /// Nought to one along a quartic Bézier that leaves and arrives at rest and runs past one in between.
    private static func overshooting(_ share: CGFloat) -> CGFloat {
        let held = min(max(share, 0), 1)
        let rest = 1 - held

        return 6 * rest * rest * held * held * overshoot + 4 * rest * held * held * held + pow(held, 4)
    }

    /// The Bézier's middle control value: past one is what carries the book beyond where it settles.
    private static let overshoot: CGFloat = 1.25

    /// How deep the book dips at its lowest, as a share of the screen's height.
    private static let dipping: CGFloat = 0.1

    /// What brings `t³ (1 − t)²` to one at its peak, three-fifths of the way; the dip arrives at rest.
    private static let dipShape: CGFloat = 3_125 / 108

    /// Nought to one, slow at both ends, for a share that may run past either.
    private static func ease(_ share: CGFloat) -> CGFloat {
        let held = min(max(share, 0), 1)

        return held * held * (3 - 2 * held)
    }

    /// How much of the run the cover takes to swing open, from its start.
    private static let opening: CGFloat = 0.85

    /// How long the cover lingers before it swings: the power its share of the turn is raised to.
    private static let lifting: CGFloat = 1.5

    /// How many flat strips the bending cover is cut into.
    private static let stripCount = 24

    /// How far each strip reaches under the next, so no hair of the page shows between them.
    private static let seam: CGFloat = 0.5

    /// All of a picture's height, as a layer's contents are cut.
    private static let wholeHeight: CGFloat = 1

    /// How far off the eye stands, in the book's own widths.
    private static let perspective: CGFloat = 3

    /// How much of the run the book's shadow takes to fade in.
    private static let leaving: CGFloat = 0.15

    private static let shadowRadius: CGFloat = 12
    private static let shadowing: CGFloat = 0.3

    /// The shade the open cover throws across the page beside the spine, and how far across it reaches.
    private static let creaseShading: CGFloat = 0.25
    private static let creaseWidth: CGFloat = 0.3
}
