//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookStorage
import DesignSystem
import SwiftUI
import UIKit

/// A book's face, printed once into a picture and kept: its artwork cut to the board, the board's edge,
/// and the crease it is bound along.
///
/// Drawn live, a board is a mask, a gradient and a stroke over every cover on screen, and a mask costs a
/// pass of its own on every frame the shelf moves. Printed, a cover is one picture. The drawing takes no
/// isolation, so it runs off the main actor; the cache belongs to the main actor.
enum CoverPrint {
    /// What a face is asked for, and everything that changes how it comes out.
    struct Order: Hashable, Sendable {
        let url: URL
        let size: CGSize
        let isDark: Bool
    }

    @MainActor
    private static let prints: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()

        cache.countLimit = 400
        // Four bytes a pixel, and a cover on a shelf is a few hundred thousand of them.
        cache.totalCostLimit = 64 * 1024 * 1024

        return cache
    }()

    @MainActor
    private static var blanks: [Bool: UIImage] = [:]

    @MainActor
    static func held(_ order: Order) -> UIImage? { prints.object(forKey: key(order)) }

    @discardableResult
    @MainActor
    static func keep(_ image: UIImage, for order: Order) -> UIImage {
        let cost = Int(image.size.width * image.scale * image.size.height * image.scale) * 4

        prints.setObject(image, forKey: key(order), cost: cost)

        return image
    }

    /// The board with no picture on it, which stands in for any face still being printed.
    ///
    /// One picture stretches to every size: its corners and the crease are held at the size they are
    /// drawn, and only the flat middle stretches.
    @MainActor
    static func blank(isDark: Bool) -> UIImage {
        if let held = blanks[isDark] { return held }

        let creased = Board.crease(.light).last?.at ?? 0
        let corner = max(Design.Radius.cover, Design.Radius.foreEdge)
        let insets = UIEdgeInsets(top: corner, left: creased, bottom: max(corner, footReach), right: corner)
        let size = CGSize(width: insets.left + insets.right + 1, height: insets.top + insets.bottom + 1)
        let drawn = draw(size: size, artwork: nil, isDark: isDark, density: SpinePrint.density)
            .resizableImage(withCapInsets: insets, resizingMode: .stretch)

        blanks[isDark] = drawn
        return drawn
    }

    /// The crease on its own, for laying over whatever is drawn on a cover after its face was printed:
    /// a binding's shadow falls on the reading line and the bookmark as it does on the artwork.
    ///
    /// As short as the lattice goes and stretched down whatever it is laid over, since nothing in a
    /// crease changes along the binding.
    @MainActor
    static func binding(isDark: Bool) -> UIImage {
        if let held = bindings[isDark] { return held }

        let scheme = UITraitCollection(userInterfaceStyle: isDark ? .dark : .light)
        let size = CGSize(width: bindingWidth, height: Design.Space.nudge)
        let format = UIGraphicsImageRendererFormat()

        format.scale = SpinePrint.density

        let drawn = UIGraphicsImageRenderer(size: size, format: format).image { drawn in
            crease(
                in: CGRect(origin: .zero, size: size),
                scheme: isDark ? .dark : .light,
                traits: scheme,
                context: drawn.cgContext
            )
        }

        bindings[isDark] = drawn
        return drawn
    }

    /// How far in from the bound edge the crease reaches.
    static var bindingWidth: CGFloat { Board.crease(.light).last?.at ?? 0 }

    @MainActor
    private static var bindings: [Bool: UIImage] = [:]

    /// The face for this order, from memory or drawn in the background on the artwork this device holds
    /// or fetches. Nothing where there is no artwork to draw, or the asking was given up.
    @MainActor
    static func printed(_ order: Order) async -> UIImage? {
        if let held = held(order) { return held }

        guard let artwork = await artwork(at: order.url, fetching: true), !Task.isCancelled else { return nil }

        return keep(await Press.shared.pull(order, artwork: artwork, density: SpinePrint.density), for: order)
    }

    /// Prints the faces a card about to come into view will show, from artwork already on the device.
    ///
    /// One set at a time, the latest asked for: a fling asks for a hundred cards it goes straight past.
    @MainActor
    static func warm(_ orders: [Order]) {
        warming?.cancel()
        warming = Task(priority: .utility) {
            for order in orders where held(order) == nil {
                guard !Task.isCancelled else { return }
                guard let artwork = await artwork(at: order.url, fetching: false) else { continue }

                keep(await Press.shared.pull(order, artwork: artwork, density: SpinePrint.density), for: order)
            }
        }
    }

    @MainActor
    private static var warming: Task<Void, Never>?

    @MainActor
    private static func artwork(at url: URL, fetching: Bool) async -> UIImage? {
        if let held = CoverImages.image(for: url) { return held }

        let cache = CoverCache.shared
        let loaded = fetching ? await cache.image(for: url) : await cache.held(for: url)

        if let loaded { CoverImages.remember(loaded, for: url) }

        return loaded
    }

    private static func key(_ order: Order) -> NSString { "\(order.hashValue)" as NSString }

    // MARK: - Drawing

    /// A face of this size, with the artwork filling the board or the board's own colour where there is
    /// none.
    static func draw(size: CGSize, artwork: UIImage?, isDark: Bool, density: CGFloat) -> UIImage {
        let bounds = CGRect(origin: .zero, size: size)
        let scheme = UITraitCollection(userInterfaceStyle: isDark ? .dark : .light)
        let format = UIGraphicsImageRendererFormat()

        format.scale = density

        return UIGraphicsImageRenderer(size: size, format: format).image { drawn in
            let context = drawn.cgContext
            let shape = board(in: bounds)

            context.addPath(shape)
            context.clip()

            if let artwork {
                artwork.draw(in: filling(bounds, with: artwork.size))
            } else {
                UIColor(Design.Surface.fill).resolvedColor(with: scheme).setFill()
                context.fill(bounds)
            }

            // The board's edge, of which only the inner half shows inside the cut.
            context.addPath(shape)
            context.setLineWidth(Design.Stroke.hairline)
            context.setStrokeColor(UIColor(Design.Surface.edge).resolvedColor(with: scheme).cgColor)
            context.strokePath()

            crease(in: bounds, scheme: isDark ? .dark : .light, traits: scheme, context: context)
            foot(in: bounds, scheme: isDark ? .dark : .light, context: context)
        }
    }

    /// How far up a board the shelf's shadow reaches, which a stretched stand-in has to hold unstretched.
    static var footReach: CGFloat { Board.foot(.light).last?.at ?? 0 }

    /// The shadow of the shelf over the foot of a board, inside whatever the context is clipped to.
    static func foot(in bounds: CGRect, scheme: ColorScheme, context: CGContext) {
        let stops = Board.foot(scheme)

        guard
            footReach > 0,
            bounds.height > footReach,
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: stops.map { UIColor($0.colour).cgColor } as CFArray,
                locations: stops.map { $0.at / footReach }
            )
        else { return }

        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: bounds.midX, y: bounds.maxY),
            end: CGPoint(x: bounds.midX, y: bounds.maxY - footReach),
            options: []
        )
    }

    /// Where a picture goes to fill a box without changing shape, cut evenly off both sides.
    private static func filling(_ box: CGRect, with picture: CGSize) -> CGRect {
        guard picture.width > 0, picture.height > 0 else { return box }

        let scale = max(box.width / picture.width, box.height / picture.height)
        let size = CGSize(width: picture.width * scale, height: picture.height * scale)

        return CGRect(
            x: box.midX - size.width / 2,
            y: box.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// The crease a cover is bound along, in points from its bound edge.
    private static func crease(in bounds: CGRect, scheme: ColorScheme, traits: UITraitCollection, context: CGContext) {
        let stops = Board.crease(scheme)

        guard
            bounds.width > 0,
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: stops.map { UIColor($0.colour).resolvedColor(with: traits).cgColor } as CFArray,
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
}

extension UIImageView {
    /// A picture drawn in the background, faded in over whatever stood there, where it can be seen.
    func arrive(_ picture: UIImage) {
        guard window != nil else { return image = picture }

        UIView.transition(
            with: self,
            duration: ArrivalMotion.fadeSeconds,
            options: [ .transitionCrossDissolve, .allowUserInteraction ]
        ) {
            self.image = picture
        }
    }
}

/// Where faces are drawn, off the main actor.
private actor Press {
    static let shared = Press()

    func pull(_ order: CoverPrint.Order, artwork: UIImage, density: CGFloat) -> UIImage {
        CoverPrint.draw(size: order.size, artwork: artwork, isDark: order.isDark, density: density)
    }
}
