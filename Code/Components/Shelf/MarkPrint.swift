//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import DesignSystem
import UIKit

/// The little marks a cover carries, printed once each and kept.
///
/// A shelf shows the same handful of marks on every book, so each is drawn once at its own size and
/// handed out. What varies is how far a book has been read, which is rounded to a step small enough
/// that no reader can see the rounding and large enough that a library shares its pictures.
@MainActor
enum MarkPrint {
    private static let prints = NSCache<NSString, UIImage>()

    /// A glyph in a circle, for a mark that sits on artwork.
    static func circle(_ systemImage: String, tint: UIColor, isDark: Bool) -> UIImage {
        printed("circle|\(systemImage)|\(tint.hashValue)|\(isDark)") { context in
            ground(isDark: isDark, in: context)
            glyph(systemImage, weight: .regular, tint: tint, in: context)
        }
    }

    /// A wedge that fills as something is read, closing to a full disc and a tick once it is done.
    static func progress(_ progress: Double, isComplete: Bool, isDark: Bool) -> UIImage {
        let step = (min(1, max(0, progress)) * Double(Self.steps)).rounded() / Double(Self.steps)

        return printed("progress|\(step)|\(isComplete)|\(isDark)") { context in
            let bounds = CGRect(origin: .zero, size: size)

            ground(isDark: isDark, in: context)
            resolved(UIColor(Design.Surface.edge), isDark: isDark).setFill()
            context.cgContext.fillEllipse(in: bounds)

            guard
                !isComplete
            else {
                resolved(UIColor(Design.Palette.accent), isDark: isDark).setFill()
                context.cgContext.fillEllipse(in: bounds)
                glyph("checkmark", weight: .bold, tint: .white, in: context)
                return
            }

            sector(sweep(of: step), in: bounds, isDark: isDark, context: context.cgContext)
        }
    }

    // MARK: - The parts every mark is made of

    private static let size = CGSize(width: Design.Size.mark, height: Design.Size.mark)

    /// How finely a wedge is cut. A hundredth of a book is a fifth of a degree, which nobody can see
    /// and every book on the shelf would otherwise have a picture of its own.
    private static let steps = 40

    /// The ground a mark on artwork brings with it, so a pale glyph still reads over a pale cover.
    ///
    /// A colour rather than the material the app's own asides stand on: a live blur behind every mark
    /// on every cover is a filter per book, and at this size the two cannot be told apart.
    private static func ground(isDark: Bool, in context: UIGraphicsImageRendererContext) {
        resolved(.systemBackground, isDark: isDark).withAlphaComponent(0.7).setFill()
        context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
    }

    private static func glyph(
        _ systemImage: String,
        weight: UIImage.SymbolWeight,
        tint: UIColor,
        in context: UIGraphicsImageRendererContext
    ) {
        let configuration = UIImage.SymbolConfiguration(
            pointSize: Design.Size.glyph(in: Design.Size.mark),
            weight: weight
        )

        guard
            let image = UIImage(systemName: systemImage, withConfiguration: configuration)?
                .withTintColor(tint, renderingMode: .alwaysOriginal)
        else { return }

        image.draw(at: CGPoint(x: (size.width - image.size.width) / 2, y: (size.height - image.size.height) / 2))
    }

    /// A wedge of a circle, swept clockwise from the top.
    private static func sector(_ sweep: Double, in bounds: CGRect, isDark: Bool, context: CGContext) {
        guard sweep > 0 else { return }

        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = UIBezierPath()

        path.move(to: centre)
        path.addArc(
            withCenter: centre,
            radius: bounds.width / 2,
            startAngle: -.pi / 2,
            endAngle: -.pi / 2 + 2 * .pi * sweep,
            clockwise: true
        )
        path.close()

        resolved(UIColor(Design.Palette.accent), isDark: isDark).setFill()
        path.fill()
    }

    /// Nothing read draws nothing. Everything else is scaled into the band between the two limits, so
    /// the wedge grows the whole way without ever reaching either end by accident.
    private static func sweep(of progress: Double) -> Double {
        guard progress > 0 else { return 0 }

        return narrowestStarted + progress * (widestUnfinished - narrowestStarted)
    }

    private static let widestUnfinished = 0.95
    private static let narrowestStarted = 0.06

    private static func resolved(_ colour: UIColor, isDark: Bool) -> UIColor {
        colour.resolvedColor(with: UITraitCollection(userInterfaceStyle: isDark ? .dark : .light))
    }

    private static func printed(_ key: String, _ draw: (UIGraphicsImageRendererContext) -> Void) -> UIImage {
        if let held = prints.object(forKey: key as NSString) { return held }

        let image = UIGraphicsImageRenderer(size: size).image(actions: draw)

        prints.setObject(image, forKey: key as NSString)

        return image
    }
}
