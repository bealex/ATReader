//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import DesignSystem
import SwiftUI
import UIKit

/// One side of a volume between two the reader holds that they don't.
///
/// Drawn as the book that isn't there would be drawn, so a gap turns with its run and keeps its place in
/// it rather than being listed elsewhere. The edge takes a spine's shape and shading and the face a
/// cover's, since a gap standing face-on that still looked like a spine reads as a widened spine.
final class GapView: UIImageView {
    /// Which side of the book that isn't there this stands for.
    enum Side: Hashable {
        case edge
        case face
    }

    var side = Side.edge {
        didSet {
            guard oldValue != side else { return }

            reprint()
        }
    }

    var number = 0 {
        didSet {
            guard oldValue != number else { return }

            reprint()
        }
    }

    /// A gap is printed only while it shows: every book carries a pair of them, hidden unless the book
    /// is a volume nobody holds.
    override var isHidden: Bool {
        didSet {
            guard oldValue != isHidden, !isHidden else { return }

            reprint()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        registerForTraitChanges([ UITraitUserInterfaceStyle.self ]) { (self: Self, _) in self.reprint() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()

        reprint()
    }

    private func reprint() {
        guard !isHidden, bounds.width > 0, bounds.height > 0 else { return }

        let wanted = GapPrint.image(GapPrint.Order(
            side: side,
            number: number,
            size: bounds.size,
            isDark: traitCollection.userInterfaceStyle == .dark
        ))

        guard image !== wanted else { return }

        image = wanted
    }
}

/// A volume nobody holds, printed once into a picture and kept.
///
/// A gap is made of a handful of things that repeat across a library: which side of it, how big it
/// stands, which volume it is and which way the room runs. Printing it means a shelf of them carries a
/// picture apiece rather than drawing two gradients and a plate every time one is laid out.
///
/// Half there, and half of everything it is made of: a fade laid over the whole thing takes the shading
/// down to a quarter and flattens it.
@MainActor
enum GapPrint {
    /// What a gap is asked for, and everything that changes how it comes out.
    struct Order: Hashable {
        let side: GapView.Side
        let number: Int
        let size: CGSize
        let isDark: Bool
    }

    private static let prints: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()

        cache.countLimit = 2000
        cache.totalCostLimit = 16 * 1024 * 1024

        return cache
    }()

    static func image(_ order: Order) -> UIImage? {
        guard order.size.width > 0, order.size.height > 0 else { return nil }

        let key = "\(order.hashValue)" as NSString

        if let held = prints.object(forKey: key) { return held }

        let drawn = draw(order)
        let bytes = Int(drawn.size.width * drawn.scale * drawn.size.height * drawn.scale) * 4

        prints.setObject(drawn, forKey: key, cost: bytes)

        return drawn
    }

    private static func draw(_ order: Order) -> UIImage {
        let bounds = CGRect(origin: .zero, size: order.size)
        let scheme = UITraitCollection(userInterfaceStyle: order.isDark ? .dark : .light)
        let colours = SpineInk(isDark: order.isDark)
        let shape =
            order.side == .face
            ? UIBezierPath(cgPath: CoverPrint.board(in: bounds))
            : UIBezierPath(roundedRect: bounds, cornerRadius: Design.Radius.spine)

        return UIGraphicsImageRenderer(size: order.size).image { drawn in
            let context = drawn.cgContext

            shape.addClip()
            context.setAlpha(faded)

            UIColor(Design.Surface.fill).resolvedColor(with: scheme).setFill()
            context.fill(bounds)

            if order.side == .face {
                crease(in: bounds, scheme: scheme, context: context)
            } else {
                SpinePrint.curve(in: bounds, colours: colours, context: context)
            }

            UIColor(Design.Surface.edge).resolvedColor(with: scheme).setStroke()
            shape.lineWidth = Design.Stroke.hairline
            shape.stroke()
            volume(order, in: bounds, colours: colours, context: context)
        }
    }

    /// The crease a cover is bound along, which is the one a book's own face carries.
    private static func crease(in bounds: CGRect, scheme: UITraitCollection, context: CGContext) {
        let stops = Board.crease(scheme.userInterfaceStyle == .dark ? .dark : .light)
        let colours = stops.map { UIColor($0.colour).resolvedColor(with: scheme).cgColor }

        guard
            bounds.width > 0,
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colours as CFArray,
                locations: stops.map { min(1, $0.at / bounds.width) }
            )
        else { return }

        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: bounds.minX, y: bounds.midY),
            end: CGPoint(x: bounds.maxX, y: bounds.midY),
            options: []
        )
    }

    /// Set the way a book that is here carries its own volume: along the foot of the face, and at the
    /// foot of the spine, so a gap in a run reads as one of the run rather than as a note beside it.
    private static func volume(_ order: Order, in bounds: CGRect, colours: SpineInk, context: CGContext) {
        let size = SpinePrint.plateSize(order.number)

        guard
            order.side == .edge
        else {
            let box = CGRect(
                x: bounds.midX - size.width / 2,
                y: bounds.maxY - Design.Space.extraSmall - size.height,
                width: size.width,
                height: size.height
            )

            _ = SpinePrint.plate(order.number, from: box.minX, in: box, colours: colours, context: context)
            return
        }

        context.saveGState()
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.rotate(by: -.pi / 2)

        let along = CGRect(x: -bounds.height / 2, y: -bounds.width / 2, width: bounds.height, height: bounds.width)

        _ = SpinePrint.plate(
            order.number,
            from: along.minX + Design.Space.medium,
            in: along,
            colours: colours,
            context: context
        )
        context.restoreGState()
    }

    /// How much of a book a gap is.
    private static let faded: CGFloat = 0.5
}
