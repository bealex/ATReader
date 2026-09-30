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
    private var strips: [(board: CALayer, shade: CAGradientLayer)] = []
    private let inside: CGColor
    private let paper: CGColor
    /// The ends of the pages turned with the cover, at its free edge and at the spine.
    private var edges: (fore: Edge, spine: Edge)?
    /// How thick the cover and the pages turned with it are, as a share of the book's width.
    private let depth: CGFloat
    private let pageBefore: PageBefore?
    /// The page the reader turned last, mirrored, as the back of the leaf shows it.
    private var before: CGImage?

    /// The page before the one being opened: whether it is set yet, and how to draw it at the screen's size.
    struct PageBefore {
        let isReady: @MainActor () -> Bool
        let draw: @MainActor (CGContext) -> Void
    }

    /// Lays the book out over `page`, which is already in `container` at its full size.
    ///
    /// - Parameters:
    ///   - cover: where the cover stands, in the container's space; without it the page only fades in.
    ///   - picture: the cover as drawn there; without one the page grows out of `cover` with nothing over it.
    ///   - paper: the colour of the page.
    ///   - read: how much of the book lies before the page, from nought to one.
    ///   - pageBefore: the page before the one being opened, asked after until it is ready.
    init(
        page: UIView,
        in container: UIView,
        cover: CGRect?,
        picture: UIImage?,
        paper: UIColor,
        read: CGFloat = 0,
        pageBefore: PageBefore? = nil
    ) {
        self.page = page
        self.screen = container.bounds
        self.cover = cover
        self.picture = picture?.cgImage
        self.pageBefore = pageBefore
        self.paper = Self.opaque(paper.resolvedColor(with: container.traitCollection))
        depth = Self.boardDepth + Self.bookDepth * min(max(read, 0), 1)
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

        if let picture = self.picture {
            let count = max(Self.fewestLines, Int(depth * Self.linesPerDepth))
            let pages = Self.pageEdges(paper: self.paper, count: count)
            let fore = Self.average(of: picture, from: 1 - Self.boardEdge)
            let spine = Self.average(of: picture, from: 0)

            edges = (
                Edge(in: over.layer, paper: self.paper, pages: pages, board: fore),
                Edge(in: over.layer, paper: self.paper, pages: pages, board: spine)
            )
        }
    }

    /// The end of a block of pages, as a face of its own, with the board's edge along the front.
    @MainActor
    private struct Edge {
        let face = CALayer()
        let board = CALayer()
        let shade = CALayer()

        init(in parent: CALayer, paper: CGColor, pages: CGImage?, board edgeColour: CGColor?) {
            face.anchorPoint = CGPoint(x: 0, y: 0.5)
            face.allowsEdgeAntialiasing = true
            face.backgroundColor = paper
            face.contents = pages
            face.contentsGravity = .resize
            board.backgroundColor = edgeColour ?? UIColor.darkGray.cgColor
            shade.backgroundColor = UIColor.black.cgColor
            face.addSublayer(board)
            face.addSublayer(shade)
            parent.addSublayer(face)
        }
    }

    /// Takes the book away, leaving the page standing on its own, or taking it too where the book shut.
    func remove(withPage: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Gone before it is put back to full size, or the next frame shows the whole page once more.
        if withPage { page.removeFromSuperview() }

        // SwiftUI hears where the page stands only through the view's own transform, which the run left
        // alone; without a change there, it keeps the tiny page it laid out on the way.
        page.layer.setAffineTransform(.identity)
        page.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
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

        // On the layer: a view's own transform tells SwiftUI its geometry moved, and the page lays itself
        // out again every frame.
        page.layer.setAffineTransform(
            CGAffineTransform(translationX: rect.midX - screen.midX, y: rect.midY - screen.midY)
                .scaledBy(x: scale, y: scale)
        )

        // The layer's frame skips the safe-area pass a view's frame runs, for a sheet with nothing inside.
        sheet.layer.frame = rect
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
        // Grown in as the cover lifts, so the shut book stands exactly where its cover did.
        let thickness = depth * leaf.width * Self.ease(leaf.turned / Self.thickening)
        // Hinged at the gutter by the page face, with the cover standing out from it.
        let cut = leaf.strips(strips.count)
        let covers = leaf.back(of: cut, depth: -thickness)

        if before == nil, let pageBefore, pageBefore.isReady() { before = backOfLeaf(pageBefore) }

        for (index, layers) in strips.enumerated() {
            let isFirst = index == 0
            let isLast = index == cut.count - 1
            let front = leaf.showsFront(of: cut[index], hinge: fromEye, distance: distance)
            let strip = front ? covers[index] : cut[index]

            layers.board.bounds = CGRect(x: 0, y: 0, width: strip.length + (isLast ? 0 : Self.seam), height: height)
            // A softened edge between two strips lets what is behind show through as a line.
            layers.board.edgeAntialiasingMask = CAEdgeAntialiasingMask([ .layerBottomEdge, .layerTopEdge ])
                .union(isFirst ? .layerLeftEdge : [])
                .union(isLast ? .layerRightEdge : [])
            layers.board.position = eye
            layers.board.zPosition = strip.toward + strip.length / 2 * sin(strip.angle)
            layers.board.transform = leaf.transform(of: strip, hinge: fromEye, distance: distance)
            layers.board.contents = front ? picture : before
            layers.board.backgroundColor = front ? nil : before == nil ? inside : paper

            let across = CGRect(
                x: strip.cut.lowerBound,
                y: 0,
                width: strip.cut.upperBound - strip.cut.lowerBound + (isLast ? 0 : seam),
                height: Self.wholeHeight
            )

            layers.board.contentsRect = front ? across : fitted(across, in: book.size)
            layers.shade.frame = layers.board.bounds
            layers.shade.endPoint = CGPoint(x: strip.length / layers.board.bounds.width, y: 0.5)
            // Shaded edge to edge, so neighbouring strips meet in one tone.
            layers.shade.colors = [ strip.cut.lowerBound, strip.cut.upperBound ].map {
                CGColor(gray: 0, alpha: Hinge.shading * (1 - leaf.light(at: $0)))
            }
        }

        guard let edges, let ends = leaf.edges(depth: thickness, of: covers) else { return }

        hang(edges.fore, along: ends.fore, of: leaf, over: book)
        // Only a cover still facing the eye stands off the spine; past that the pages meet at the gutter.
        if leaf.showsFront(of: cut[0], hinge: fromEye, distance: distance) {
            hang(edges.spine, along: ends.spine, of: leaf, over: book)
        } else {
            edges.spine.face.isHidden = true
        }
    }

    /// Hangs one end of the pages along `strip` of the leaf standing over `book`.
    private func hang(_ edge: Edge, along strip: Leaf.Strip, of leaf: Leaf, over book: CGRect) {
        edge.face.isHidden = strip.length < Self.leastEdge

        guard !edge.face.isHidden else { return }

        let eye = CGPoint(x: book.midX, y: book.midY)
        let fromEye = CGPoint(x: book.minX - eye.x, y: 0)
        let height = book.height

        edge.face.bounds = CGRect(x: 0, y: 0, width: strip.length, height: height)
        edge.face.position = eye
        edge.face.zPosition = strip.toward + strip.length / 2 * sin(strip.angle)
        edge.face.transform = leaf.transform(of: strip, hinge: fromEye, distance: leaf.width * Self.perspective)
        edge.board.frame = CGRect(x: 0, y: 0, width: Self.boardDepth * leaf.width, height: height)
        edge.shade.frame = edge.face.bounds
        // Lit as the end faces the eye, which is when the leaf stands on edge.
        edge.shade.opacity = Float(Hinge.shading * (1 - abs(cos(strip.angle))))
    }

    /// The part `across` of a leaf `size` large cut from the page before, fitted inside it whole as the
    /// page stands on the screen; beyond the picture its edges run on as paper.
    private func fitted(_ across: CGRect, in size: CGSize) -> CGRect {
        let scale = min(size.width / screen.width, size.height / screen.height)
        let shown = CGSize(width: screen.width * scale, height: screen.height * scale)
        let margin = CGSize(width: (size.width - shown.width) / 2, height: (size.height - shown.height) / 2)

        return CGRect(
            x: (across.minX * size.width - margin.width) / shown.width,
            y: -margin.height / shown.height,
            width: across.width * size.width / shown.width,
            height: size.height / shown.height
        )
    }

    /// The page before drawn once, mirrored on its own paper, as the back of the leaf shows it; the reader
    /// draws its paper behind its sheets rather than on them.
    private func backOfLeaf(_ pageBefore: PageBefore) -> CGImage? {
        let format = UIGraphicsImageRendererFormat.preferred()

        format.opaque = true

        return UIGraphicsImageRenderer(size: screen.size, format: format).image { drawn in
            drawn.cgContext.setFillColor(paper)
            drawn.cgContext.fill(CGRect(origin: .zero, size: screen.size))
            drawn.cgContext.translateBy(x: screen.width, y: 0)
            drawn.cgContext.scaleBy(x: -1, y: 1)
            pageBefore.draw(drawn.cgContext)
        }
        .cgImage
    }

    /// `colour` as plain sRGB, whole: a colour handed over from SwiftUI loses itself on the way to Core Graphics.
    private static func opaque(_ colour: UIColor) -> CGColor {
        var red: CGFloat = 1, green: CGFloat = 1, blue: CGFloat = 1, alpha: CGFloat = 1

        colour.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    /// Opaque paper cut into `count` pages of uneven thickness, the gaps between them uneven in shade and
    /// each drifting along its height, stretched over the end of the pages; the same `count` draws the same.
    private static func pageEdges(paper: CGColor, count: Int) -> CGImage? {
        var random = SplitMix(seed: UInt64(count))
        let thicknesses = (0 ..< count).map { _ in Int.random(in: thinnestPage ... thickestPage, using: &random) }
        let width = thicknesses.reduce(0, +)
        let height = edgeRows
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )

        context?.setFillColor(paper)
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))

        var x = 0

        for thickness in thicknesses {
            // A page a shade off its neighbours, as paper cut from different sheets is.
            context?.setFillColor(CGColor(gray: 0, alpha: CGFloat.random(in: 0 ... pageTint, using: &random)))
            context?.fill(CGRect(x: x, y: 0, width: thickness, height: height))

            let shade = CGFloat.random(in: pageLineShade, using: &random)
            let phase = CGFloat.random(in: 0 ... 2 * .pi, using: &random)
            let waves = CGFloat.random(in: 1 ... 3, using: &random)

            for row in 0 ..< height {
                let drift = 1 - lineDrift * (1 + sin(phase + waves * 2 * .pi * CGFloat(row) / CGFloat(height))) / 2

                context?.setFillColor(CGColor(gray: 0, alpha: shade * drift))
                context?.fill(CGRect(x: x, y: row, width: pixel, height: pixel))
            }

            x += thickness
        }

        return context?.makeImage()
    }

    /// A seeded generator, so the pages at a book's end come out the same each time it is drawn.
    private struct SplitMix: RandomNumberGenerator {
        var seed: UInt64

        mutating func next() -> UInt64 {
            seed &+= 0x9E37_79B9_7F4A_7C15

            var mixed = seed

            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB

            return mixed ^ (mixed >> 31)
        }
    }

    /// The colour of `picture` along a sliver of its width from `start`, opaque, for the board's own edge.
    private static func average(of picture: CGImage, from start: CGFloat) -> CGColor? {
        let x = Int(CGFloat(picture.width) * min(start, 1 - boardEdge))
        let width = max(1, Int(CGFloat(picture.width) * boardEdge))
        let inset = picture.height / 10

        guard
            let sliver = picture.cropping(to: CGRect(x: x, y: inset, width: width, height: picture.height - 2 * inset)),
            let context = CGContext(
                data: nil,
                width: pixel,
                height: pixel,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { return nil }

        context.interpolationQuality = .medium
        context.draw(sliver, in: CGRect(x: 0, y: 0, width: pixel, height: pixel))

        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

        let channel = { (index: Int) in CGFloat(bytes[index]) / CGFloat(UInt8.max) }

        return CGColor(srgbRed: channel(0), green: channel(1), blue: channel(2), alpha: 1)
    }

    private static func strip(in parent: CALayer) -> (board: CALayer, shade: CAGradientLayer) {
        let board = CALayer()
        let shade = CAGradientLayer()

        board.anchorPoint = CGPoint(x: 0, y: 0.5)
        board.allowsEdgeAntialiasing = true
        board.contentsGravity = .resize
        shade.startPoint = CGPoint(x: 0, y: 0.5)
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

    /// How thick the board is, and the whole book's pages, as shares of the book's width.
    private static let boardDepth: CGFloat = 0.012
    private static let bookDepth: CGFloat = 0.12

    /// How much of the cover picture's width, from its free edge, colours the board's own edge.
    private static let boardEdge: CGFloat = 0.02

    /// How much of its turn the leaf takes to grow to its full thickness.
    private static let thickening: CGFloat = 0.1

    /// A leaf thinner than this has no edge worth drawing.
    private static let leastEdge: CGFloat = 0.5

    /// How many lines between pages the leaf's end shows, per share of the book's width it is thick, the
    /// least it ever shows, and how dark they are.
    private static let linesPerDepth: CGFloat = 300
    private static let fewestLines = 3
    private static let pageLineShade: ClosedRange<CGFloat> = 0.03 ... 0.22

    /// How many pixels thick a page is drawn, at the thinnest and thickest, before it is stretched.
    private static let thinnestPage = 2
    private static let thickestPage = 7

    /// How dark a page may be against its neighbours, and how much a gap's shade fades along its height.
    private static let pageTint: CGFloat = 0.05
    private static let lineDrift: CGFloat = 0.6

    /// One pixel of a bitmap drawn by hand.
    private static let pixel = 1

    /// How many rows the end of the pages is drawn in, for the gaps to drift along.
    private static let edgeRows = 48

    /// The shade the open cover throws across the page beside the spine, and how far across it reaches.
    private static let creaseShading: CGFloat = 0.25
    private static let creaseWidth: CGFloat = 0.3
}
