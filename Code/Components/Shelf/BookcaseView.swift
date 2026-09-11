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
/// Drawn as a pattern down its own height rather than from the rows the shelf holds, since every row is as
/// deep as every other. A shelf turning to a different number of rows changes its height a frame at a
/// time, and the pattern simply runs on or stops short with it.
final class BookcaseView: UIView {
    /// How tall a row's books may stand, which sets how deep every row is.
    var slot: CGFloat = 0 {
        didSet {
            guard oldValue != slot else { return }

            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
        layer.cornerRadius = Design.Radius.small
        layer.cornerCurve = .continuous
        clipsToBounds = true

        registerForTraitChanges([ UITraitUserInterfaceStyle.self ]) { (self: Self, _) in self.setNeedsDisplay() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard slot > 0, let context = UIGraphicsGetCurrentContext() else { return }

        let scheme: ColorScheme = traitCollection.userInterfaceStyle == .dark ? .dark : .light

        plank(CGRect(x: 0, y: 0, width: bounds.width, height: ShelfLayout.lid), scheme: scheme, context: context)

        var top = ShelfLayout.lid

        while top < bounds.height {
            let inside = CGRect(x: 0, y: top, width: bounds.width, height: ShelfLayout.headroom + slot)

            self.inside(inside, scheme: scheme, context: context)
            plank(
                CGRect(x: 0, y: inside.maxY, width: bounds.width, height: ShelfLayout.plank),
                scheme: scheme,
                context: context
            )
            top += ShelfLayout.step(slot: slot)
        }
    }

    private func inside(_ box: CGRect, scheme: ColorScheme, context: CGContext) {
        let stops = Bookcase.inside(scheme)

        gradient(
            in: box,
            colours: stops.map { UIColor($0.colour).cgColor },
            locations: stops.map(\.at),
            context: context
        )
    }

    /// A plank seen from the front, lit along its top edge and falling away below.
    private func plank(_ box: CGRect, scheme: ColorScheme, context: CGContext) {
        let base = UIColor(Bookcase.plank(scheme)).resolvedColor(with: traitCollection)
        let pixel = 1 / max(1, traitCollection.displayScale)

        gradient(
            in: box,
            colours: [
                Self.mixed(base, with: .white, by: Bookcase.plankLift).cgColor,
                base.cgColor,
                Self.mixed(base, with: .black, by: Bookcase.plankFall).cgColor,
            ],
            locations: [ 0, 0.3, 1 ],
            context: context
        )

        UIColor(Bookcase.plankHighlight(scheme)).setFill()
        context.fill(CGRect(x: box.minX, y: box.minY, width: box.width, height: pixel))

        UIColor(Bookcase.plankShadow).setFill()
        context.fill(CGRect(x: box.minX, y: box.maxY - pixel, width: box.width, height: pixel))
    }

    private func gradient(in box: CGRect, colours: [CGColor], locations: [CGFloat], context: CGContext) {
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
        let to = components(of: other)

        return UIColor(
            red: from[0] + (to[0] - from[0]) * part,
            green: from[1] + (to[1] - from[1]) * part,
            blue: from[2] + (to[2] - from[2]) * part,
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
