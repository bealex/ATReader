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
///
/// Half there, and half of everything it is made of: a fade laid over the whole thing takes the shading
/// down to a quarter and flattens it.
final class GapView: UIView {
    /// Which side of the book that isn't there this stands for.
    enum Side {
        case edge
        case face
    }

    var side = Side.edge {
        didSet { setNeedsDisplay() }
    }

    var number = 0 {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .clear
        isOpaque = false
        registerForTraitChanges([ UITraitUserInterfaceStyle.self ]) { (self: Self, _) in self.setNeedsDisplay() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        let isDark = traitCollection.userInterfaceStyle == .dark
        let colours = SpineInk(isDark: isDark)
        let shape =
            side == .face
            ? UIBezierPath(cgPath: CoverView.board(in: bounds))
            : UIBezierPath(roundedRect: bounds, cornerRadius: Design.Radius.spine)

        context.saveGState()
        shape.addClip()
        context.setAlpha(Self.faded)

        UIColor(Design.Surface.fill).resolvedColor(with: traitCollection).setFill()
        context.fill(bounds)

        if side == .face {
            crease(in: bounds, isDark: isDark, context: context)
        } else {
            SpinePrint.curve(in: bounds, colours: colours, context: context)
        }

        UIColor(Design.Surface.edge).resolvedColor(with: traitCollection).setStroke()
        shape.lineWidth = Design.Stroke.hairline
        shape.stroke()
        volume(in: bounds, colours: colours, context: context)
        context.restoreGState()
    }

    /// The crease a cover is bound along, which is the one a book's own face carries.
    private func crease(in bounds: CGRect, isDark: Bool, context: CGContext) {
        let stops = Board.crease(isDark ? .dark : .light)
        let colours = stops.map { UIColor($0.colour).resolvedColor(with: traitCollection).cgColor }

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
    private func volume(in bounds: CGRect, colours: SpineInk, context: CGContext) {
        let size = SpinePrint.plateSize(number)

        guard
            side == .edge
        else {
            let box = CGRect(
                x: bounds.midX - size.width / 2,
                y: bounds.maxY - Design.Space.extraSmall - size.height,
                width: size.width,
                height: size.height
            )

            _ = SpinePrint.plate(number, from: box.minX, in: box, colours: colours, context: context)
            return
        }

        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.rotate(by: -.pi / 2)

        let along = CGRect(x: -bounds.height / 2, y: -bounds.width / 2, width: bounds.height, height: bounds.width)

        _ = SpinePrint.plate(
            number,
            from: along.minX + Design.Space.medium,
            in: along,
            colours: colours,
            context: context
        )
    }

    /// How much of a book a gap is.
    private static let faded: CGFloat = 0.5
}
