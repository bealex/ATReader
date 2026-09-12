//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import DesignSystem
import SwiftUI
import UIKit

/// The bookcase behind a shelf's books: a board across the top, then for each row a dark inside and the
/// plank the row stands on.
///
/// Laid as a pattern down its own height rather than from the rows the shelf holds, since every row is as
/// deep as every other. A shelf turning to a different number of rows changes its height a frame at a
/// time, and the pattern simply runs on or stops short with it. Every piece is a picture printed once and
/// shared by every card, so a card coming into view or changing height draws nothing.
final class BookcaseView: UIView {
    /// How tall a row's books may stand, which sets how deep every row is.
    var slot: CGFloat = 0 {
        didSet {
            guard oldValue != slot else { return }

            setNeedsLayout()
        }
    }

    private let lid = CALayer()
    private var rows: [CALayer] = []
    /// The screen's own colour laid over each corner, which rounds the bookcase without clipping it: a
    /// layer clipped to a rounded shape with others inside it is drawn off screen on every frame.
    private let corners = (0 ..< 4).map { _ in CALayer() }
    /// What the pieces now hanging were printed for.
    private var painted: (slot: CGFloat, isDark: Bool)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        isOpaque = false
        isUserInteractionEnabled = false
        layer.addSublayer(lid)

        for corner in corners { layer.addSublayer(corner) }

        registerForTraitChanges([ UITraitUserInterfaceStyle.self ]) { (self: Self, _) in
            self.painted = nil
            self.setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard
            slot > 0
        else {
            for part in [ lid ] + rows + corners { part.isHidden = true }
            return
        }

        let isDark = traitCollection.userInterfaceStyle == .dark
        let step = ShelfLayout.step(slot: slot)
        let count = max(0, Int(((bounds.height - ShelfLayout.lid) / step).rounded(.up)))

        while rows.count < count {
            let row = CALayer()

            layer.insertSublayer(row, below: corners[0])
            rows.append(row)
        }

        if painted?.slot != slot || painted?.isDark != isDark {
            hang(BookcasePrint.lid(isDark: isDark), on: lid)

            for row in rows { hang(BookcasePrint.row(slot: slot, isDark: isDark), on: row) }

            for corner in corners { hang(BookcasePrint.corner(isDark: isDark), on: corner) }

            painted = (slot, isDark)
        }

        lid.isHidden = false
        lid.frame = CGRect(x: 0, y: 0, width: bounds.width, height: ShelfLayout.lid)

        for (index, row) in rows.enumerated() {
            row.isHidden = index >= count

            if row.contents == nil { hang(BookcasePrint.row(slot: slot, isDark: isDark), on: row) }

            row.frame = CGRect(x: 0, y: ShelfLayout.lid + CGFloat(index) * step, width: bounds.width, height: step)
        }

        place(corners)
    }

    private func hang(_ image: UIImage, on part: CALayer) {
        part.contents = image.cgImage
        part.contentsScale = image.scale
    }

    /// Each corner's cap, turned to face its own corner.
    private func place(_ corners: [CALayer]) {
        let size = BookcasePrint.cornerSize
        let spots: [(CGPoint, CGAffineTransform)] = [
            (CGPoint(x: 0, y: 0), .identity),
            (CGPoint(x: bounds.width - size, y: 0), CGAffineTransform(scaleX: -1, y: 1)),
            (CGPoint(x: 0, y: bounds.height - size), CGAffineTransform(scaleX: 1, y: -1)),
            (CGPoint(x: bounds.width - size, y: bounds.height - size), CGAffineTransform(scaleX: -1, y: -1)),
        ]

        for (corner, (origin, turn)) in zip(corners, spots) {
            corner.isHidden = false
            corner.setAffineTransform(.identity)
            corner.frame = CGRect(origin: origin, size: CGSize(width: size, height: size))
            corner.setAffineTransform(turn)
        }
    }
}

/// The pieces a bookcase is built of, printed once and kept.
///
/// Nothing in a bookcase changes across its width, so each piece is a picture a point wide, stretched to
/// whatever width the card has.
@MainActor
enum BookcasePrint {
    private static var prints: [String: UIImage] = [:]

    /// The board across the top.
    static func lid(isDark: Bool) -> UIImage {
        kept("lid-\(isDark)") {
            printed(height: ShelfLayout.lid, isDark: isDark) { box, scheme, context in
                plank(box, scheme: scheme, context: context)
            }
        }
    }

    /// One row: the dark inside the books stand in, and the plank under them.
    static func row(slot: CGFloat, isDark: Bool) -> UIImage {
        kept("row-\(slot)-\(isDark)") {
            printed(height: ShelfLayout.step(slot: slot), isDark: isDark) { box, scheme, context in
                let inside = CGRect(x: box.minX, y: box.minY, width: box.width, height: ShelfLayout.headroom + slot)

                self.inside(inside, scheme: scheme, context: context)
                plank(
                    CGRect(x: box.minX, y: inside.maxY, width: box.width, height: ShelfLayout.plank),
                    scheme: scheme,
                    context: context
                )
            }
        }
    }

    /// How big a corner's cap is: room for the whole of a continuous corner's curve, which runs further
    /// along each side than its radius.
    static var cornerSize: CGFloat { Design.Radius.small * 2 }

    /// The screen's colour outside the top left corner of a rounded bookcase, clear inside it.
    static func corner(isDark: Bool) -> UIImage {
        kept("corner-\(isDark)") {
            let size = CGSize(width: cornerSize, height: cornerSize)
            let traits = UITraitCollection(userInterfaceStyle: isDark ? .dark : .light)
            let format = UIGraphicsImageRendererFormat()

            format.scale = SpinePrint.density

            return UIGraphicsImageRenderer(size: size, format: format).image { drawn in
                let context = drawn.cgContext
                let rounded = UIBezierPath(
                    roundedRect: CGRect(origin: .zero, size: CGSize(width: size.width * 4, height: size.height * 4)),
                    cornerRadius: Design.Radius.small
                )

                UIColor(Design.Surface.screen).resolvedColor(with: traits).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                context.setBlendMode(.clear)
                rounded.fill()
            }
        }
    }

    private static func kept(_ key: String, print: () -> UIImage) -> UIImage {
        if let held = prints[key] { return held }

        let made = print()

        prints[key] = made
        return made
    }

    private static func printed(
        height: CGFloat,
        isDark: Bool,
        drawing: (CGRect, ColorScheme, CGContext) -> Void
    ) -> UIImage {
        // Any width does, since nothing changes across a bookcase; the layer stretches it to the card.
        let size = CGSize(width: Design.Space.unit, height: height)
        let format = UIGraphicsImageRendererFormat()

        format.scale = SpinePrint.density

        // Dynamic colours turned into Core Graphics ones resolve against whatever traits are current.
        let traits = UITraitCollection(userInterfaceStyle: isDark ? .dark : .light)

        return UIGraphicsImageRenderer(size: size, format: format).image { drawn in
            traits.performAsCurrent {
                drawing(CGRect(origin: .zero, size: size), isDark ? .dark : .light, drawn.cgContext)
            }
        }
    }

    private static func inside(_ box: CGRect, scheme: ColorScheme, context: CGContext) {
        let stops = Bookcase.inside(scheme)

        gradient(
            in: box,
            colours: stops.map { UIColor($0.colour).cgColor },
            locations: stops.map(\.at),
            context: context
        )
    }

    /// A plank seen from the front, lit along its top edge and falling away below.
    private static func plank(_ box: CGRect, scheme: ColorScheme, context: CGContext) {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let base = UIColor(Bookcase.plank(scheme)).resolvedColor(with: traits)
        let pixel = 1 / SpinePrint.density

        gradient(
            in: box,
            colours: [
                mixed(base, with: .white, by: Bookcase.plankLift).cgColor,
                base.cgColor,
                mixed(base, with: .black, by: Bookcase.plankFall).cgColor,
            ],
            locations: [ 0, 0.3, 1 ],
            context: context
        )

        UIColor(Bookcase.plankHighlight(scheme)).setFill()
        context.fill(CGRect(x: box.minX, y: box.minY, width: box.width, height: pixel))

        UIColor(Bookcase.plankShadow).setFill()
        context.fill(CGRect(x: box.minX, y: box.maxY - pixel, width: box.width, height: pixel))
    }

    private static func gradient(in box: CGRect, colours: [CGColor], locations: [CGFloat], context: CGContext) {
        guard
            box.height > 0,
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colours as CFArray,
                locations: locations
            )
        else { return }

        context.saveGState()
        context.clip(to: box)
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: box.midX, y: box.minY),
            end: CGPoint(x: box.midX, y: box.maxY),
            options: []
        )
        context.restoreGState()
    }

    /// One colour taken part of the way towards another.
    private static func mixed(_ colour: UIColor, with other: UIColor, by part: CGFloat) -> UIColor {
        let from = components(of: colour)
        let onto = components(of: other)

        return UIColor(
            red: from[0] + (onto[0] - from[0]) * part,
            green: from[1] + (onto[1] - from[1]) * part,
            blue: from[2] + (onto[2] - from[2]) * part,
            alpha: from[3]
        )
    }

    /// Red, green, blue and alpha, in that order.
    private static func components(of colour: UIColor) -> [CGFloat] {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        colour.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return [ red, green, blue, alpha ]
    }
}
