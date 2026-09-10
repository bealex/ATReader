//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import CoreImage
import CoreImage.CIFilterBuiltins
import DesignSystem
import UIKit

/// A book's spine, printed once into a picture and kept.
///
/// Everything on a spine is settled before it is drawn: the title, the volume, and a cover thrown out of
/// focus. Printing it means a shelf of five hundred books carries five hundred bitmaps instead of five
/// hundred live blurs, and the turn moves a picture rather than a filter.
///
/// The drawing takes no isolation of its own, so `SpinePress` can run it ahead of the reader. Only the
/// cache and what it remembers belong to the main actor.
enum SpinePrint {
    /// What a spine is asked for, and everything that changes how it comes out.
    struct Order: Hashable {
        let id: Int
        let number: Int?
        let title: String
        let size: CGSize
        let isDark: Bool
        /// Whether the cover was here to print. A spine printed before its artwork arrived is asked
        /// for again once it has.
        let hasArtwork: Bool
    }

    /// A spine off the press: the picture, and which way the book's own colour turned out to run.
    struct Impression {
        let image: UIImage
        let isDark: Bool
    }

    /// How many spines are kept, and how much memory they may take between them.
    static let keptCount = 10_000
    static let keptBytes = 100 * 1024 * 1024

    @MainActor
    private static let prints: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()

        cache.countLimit = keptCount
        cache.totalCostLimit = keptBytes

        return cache
    }()

    /// Which way each book's own colour ran, once its spine has been printed, so a cover can set its
    /// own plate in what the spine was set in.
    @MainActor
    private static var darkness: [Int: Bool] = [:]

    @MainActor
    static func isDark(of id: Int) -> Bool? { darkness[id] }

    @MainActor
    static func image(of work: Book, number: Int?, title: String, size: CGSize, isDark: Bool) -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }

        func order(hasArtwork: Bool) -> Order {
            Order(id: work.id, number: number, title: title, size: size, isDark: isDark, hasArtwork: hasArtwork)
        }

        // A spine already printed on its own artwork stands whatever is in memory now: a cover dropped
        // to make room for another doesn't make the spine printed on it wrong.
        if let held = held(order(hasArtwork: true)) { return held }

        let artwork = work.coverURL.flatMap(CoverImages.image(for:))
        let wanted = order(hasArtwork: artwork != nil)

        if let held = held(wanted) { return held }

        return keep(draw(wanted, artwork: artwork, density: density, context: context), for: wanted)
    }

    /// Whether this spine has been printed already, so a press working ahead of the reader can pass
    /// over it without drawing.
    @MainActor
    static func has(_ order: Order) -> Bool { held(order) != nil }

    /// Files a spine, whoever printed it.
    @discardableResult
    @MainActor
    static func keep(_ impression: Impression, for order: Order) -> UIImage {
        darkness[order.id] = impression.isDark
        prints.setObject(impression.image, forKey: key(order), cost: bytes(of: impression.image))

        return impression.image
    }

    @MainActor
    static func forget() { prints.removeAllObjects() }

    /// How many pixels a point is here, which a press off the main actor is told rather than asks.
    @MainActor
    static var density: CGFloat { UIScreen.main.scale }

    @MainActor
    private static func held(_ order: Order) -> UIImage? { prints.object(forKey: key(order)) }

    private static func key(_ order: Order) -> NSString { "\(order.hashValue)" as NSString }

    private static func bytes(of image: UIImage) -> Int {
        Int(image.size.width * image.scale * image.size.height * image.scale) * 4
    }

    static func draw(_ order: Order, artwork: UIImage?, density: CGFloat, context: CIContext) -> Impression {
        let bounds = CGRect(origin: .zero, size: order.size)
        let (ground, colours) = ground(
            artwork,
            in: bounds,
            shelfIsDark: order.isDark,
            density: density,
            context: context
        )
        // Given rather than taken from the screen, which off the main actor is nobody's to read.
        let format = UIGraphicsImageRendererFormat()

        format.scale = density

        let image = UIGraphicsImageRenderer(size: order.size, format: format).image { drawn in
            let cg = drawn.cgContext

            UIBezierPath(roundedRect: bounds, cornerRadius: Design.Radius.spine).addClip()
            ground.draw(in: bounds)
            colours.wash.setFill()
            cg.fill(bounds)
            curve(in: bounds, colours: colours, context: cg)
            binding(in: bounds, colours: colours, density: density, context: cg)
            writing(order, in: bounds, colours: colours, context: cg)
        }

        return Impression(image: image, isDark: colours.isDark)
    }

    // MARK: - The cover, out of focus

    /// The book's own cover thrown far enough out of focus to be colour rather than picture, and which
    /// way round the spine printed on it has to be treated.
    ///
    /// A dark cover is given the dark treatment and a light one the light, whatever the room is doing:
    /// what the writing on a spine has to stand against is the picture under it, and a shelf holds both
    /// kinds of book at once. Only a book whose cover has not arrived takes the shelf's own scheme,
    /// having nothing else to go on.
    ///
    /// Worked in pixels rather than points throughout: a picture's extent is in pixels and its size is
    /// in points, and mixing the two crops a different part of the cover on every device.
    private static func ground(
        _ artwork: UIImage?,
        in bounds: CGRect,
        shelfIsDark: Bool,
        density: CGFloat,
        context: CIContext
    ) -> (UIImage, SpineInk) {
        guard
            let artwork,
            let source = CIImage(image: artwork)
        else {
            let colours = SpineInk(isDark: shelfIsDark)
            let format = UIGraphicsImageRendererFormat()

            format.scale = density

            let flat = UIGraphicsImageRenderer(size: bounds.size, format: format).image { drawn in
                colours.bare.setFill()
                drawn.cgContext.fill(bounds)
            }

            return (flat, colours)
        }

        let across = CGRect(origin: .zero, size: CGSize(width: bounds.width * density, height: bounds.height * density))
        let filled = fill(source, of: across.size)
        let blurred = filled.applyingGaussianBlur(sigma: Design.Size.spineBlur * density)
        let colours = SpineInk(isDark: isDark(blurred, in: across, context: context))
        let controls = CIFilter.colorControls()
        controls.inputImage = blurred
        controls.saturation = Float(colours.saturation)
        controls.brightness = Float(colours.brightness)

        // A ceiling on a dark shelf and a floor on a light one, taken per channel so a colour keeps its
        // hue and gives up only what stood past the line.
        let held = CIImage(color: CIColor(color: colours.limit))
        let blend = colours.isDark ? CIFilter.darkenBlendMode() : CIFilter.lightenBlendMode()
        blend.inputImage = held
        blend.backgroundImage = controls.outputImage

        guard
            let output = blend.outputImage,
            let made = context.createCGImage(output, from: across)
        else { return (UIImage(), colours) }

        return (UIImage(cgImage: made, scale: density, orientation: .up), colours)
    }

    /// How dark a spine's own colour is, averaged over the whole of it.
    ///
    /// Measured on the blurred cover before anything is done to it, since what the treatment is chosen
    /// for is the picture, and the treatment is what would otherwise decide the answer.
    private static func isDark(_ ground: CIImage, in across: CGRect, context: CIContext) -> Bool {
        let average = CIFilter.areaAverage()
        average.inputImage = ground
        average.extent = across

        guard let output = average.outputImage else { return false }

        var pixel = [UInt8](repeating: 0, count: 4)

        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: whole, height: whole),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )

        let light = 0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2])

        return light < Self.halfLit
    }

    /// How light a spine may be and still be treated as a dark one, out of a channel's full 255.
    private static let halfLit = 128.0

    /// What an average comes back as, which is one pixel holding the whole of it.
    private static let whole: CGFloat = 1

    /// The cover scaled to cover the spine and moved so the middle of it lands on the origin, which is
    /// what filling a narrow box with a wide picture means.
    ///
    /// Counted in pixels, since that is what a picture's extent is counted in, and the extent is read
    /// before the edges are held out: a clamped picture reaches everywhere and measures nothing.
    private static func fill(_ image: CIImage, of size: CGSize) -> CIImage {
        let extent = image.extent
        let scale = max(size.width / extent.width, size.height / extent.height)
        let across = (extent.width * scale - size.width) / 2
        let down = (extent.height * scale - size.height) / 2
        let placed = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: -across, y: -down))

        // Held out past its own edges, so the blur has something to reach for at the head and the foot
        // rather than pulling in nothing and fading the ends out.
        return image.transformed(by: placed).clampedToExtent()
    }

    /// Worked in the colours the rest of the app is drawn in. Left to itself CoreImage works in linear
    /// light, where the same saturation and the same blend come out somewhere else entirely.
    static func makeContext() -> CIContext {
        guard
            let sRGB = CGColorSpace(name: CGColorSpace.sRGB)
        else { return CIContext(options: [ .useSoftwareRenderer: false ]) }

        return CIContext(options: [ .useSoftwareRenderer: false, .workingColorSpace: sRGB ])
    }

    /// The shelf's own, for a spine printed the moment it is asked for. A press keeps one of its own,
    /// since a context belongs to whoever draws with it.
    @MainActor
    private static let context = makeContext()

    // MARK: - The board

    /// The light falling across a spine: both edges turn away from it, the middle catches it, and the
    /// very edge of the board is dark.
    static func curve(in bounds: CGRect, colours: SpineInk, context: CGContext) {
        let stops = colours.curve

        guard
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: stops.map(\.0.cgColor) as CFArray,
                locations: stops.map(\.1)
            )
        else { return }

        context.saveGState()
        context.clip(to: bounds)
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: bounds.minX, y: bounds.midY),
            end: CGPoint(x: bounds.maxX, y: bounds.midY),
            options: []
        )
        context.restoreGState()
    }

    /// How a bound book is put together, which is what the eye reads as a spine rather than a bar: a
    /// pale head where the paper shows, and a dark foot.
    private static func binding(in bounds: CGRect, colours: SpineInk, density: CGFloat, context: CGContext) {
        // A line the device can draw, rather than a length that lands across two pixels: half of one
        // and half of the next is half the line, twice as wide and too faint to read as an edge.
        let pixel = 1 / density

        colours.head.setFill()
        context.fill(CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: pixel))

        colours.foot.setFill()
        context.fill(CGRect(x: bounds.minX, y: bounds.maxY - pixel, width: bounds.width, height: pixel))
    }

    // MARK: - What is printed on it

    /// Set along the spine, read from the foot upwards, with the volume nearest the bottom edge.
    ///
    /// Laid out sideways and then turned, so a leading edge here is the foot of the spine and the
    /// offsets of the stamping are given in the writing's own space.
    private static func writing(_ order: Order, in bounds: CGRect, colours: SpineInk, context: CGContext) {
        context.saveGState()
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.rotate(by: -.pi / 2)

        let along = CGRect(x: -bounds.height / 2, y: -bounds.width / 2, width: bounds.height, height: bounds.width)
        var x = along.minX + Design.Space.medium

        if let number = order.number {
            x = plate(number, from: x, in: along, colours: colours, context: context) + Design.Space.small
        }

        let room = along.maxX - Design.Space.nudge - x

        if room > 0 {
            stamp(
                order.title,
                font: Self.title,
                // Half a point to the left of the plate below it, once the spine is stood on end.
                at: CGPoint(x: x, y: along.midY - Design.Stroke.hairline),
                width: room,
                colours: colours
            )
        }

        context.restoreGState()
    }

    /// The volume on its plate as a picture of its own, so a cover carries the same one its spine does.
    @MainActor
    static func plate(_ number: Int, isDark: Bool) -> UIImage {
        let key = "plate|\(number)|\(isDark)" as NSString

        if let held = prints.object(forKey: key) { return held }

        let colours = SpineInk(isDark: isDark)
        let size = plateSize(number)
        let drawn = UIGraphicsImageRenderer(size: size).image { context in
            _ = plate(
                number,
                from: 0,
                in: CGRect(origin: .zero, size: size),
                colours: colours,
                context: context.cgContext
            )
        }

        prints.setObject(drawn, forKey: key, cost: bytes(of: drawn))

        return drawn
    }

    /// How much room a volume's plate takes, for whoever has to centre one.
    static func plateSize(_ number: Int) -> CGSize {
        let size = NSAttributedString(string: number.formatted(.number), attributes: [ .font: plate ]).size()

        return CGSize(width: size.width + Design.Space.extraSmall * 2, height: size.height + Design.Space.nudge * 2)
    }

    /// The volume, on a little plate at the foot of a spine, the way a numbered set carries its number.
    static func plate(
        _ number: Int,
        from x: CGFloat,
        in along: CGRect,
        colours: SpineInk,
        context: CGContext
    ) -> CGFloat {
        let text = NSAttributedString(
            string: number.formatted(.number),
            attributes: [ .font: Self.plate, .foregroundColor: colours.ink ]
        )
        let size = text.size()
        let box = CGRect(
            x: x,
            y: along.midY - (size.height + Design.Space.nudge * 2) / 2,
            width: size.width + Design.Space.extraSmall * 2,
            height: size.height + Design.Space.nudge * 2
        )
        let shape = UIBezierPath(roundedRect: box, cornerRadius: Design.Radius.spine)

        colours.plate.setFill()
        shape.fill()
        colours.plateEdge.setStroke()
        shape.lineWidth = Design.Stroke.hairline
        shape.stroke()
        text.draw(at: CGPoint(x: box.minX + Design.Space.extraSmall, y: box.minY + Design.Space.nudge))

        return box.maxX
    }

    /// Pressed in rather than raised: the shadow falls along the top of each letter, where the light
    /// cannot reach into the impression, and the lit edge sits below it.
    private static func stamp(
        _ words: String,
        font: UIFont,
        at point: CGPoint,
        width: CGFloat,
        colours: SpineInk
    ) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail

        let text = NSAttributedString(
            string: words,
            attributes: [ .font: font, .foregroundColor: colours.ink, .paragraphStyle: style ]
        )
        let box = CGRect(x: point.x, y: point.y - text.size().height / 2, width: width, height: text.size().height)
        let hairline = Design.Stroke.hairline

        for (colour, offset) in [ (colours.highlight, -hairline), (colours.relief, hairline) ] {
            NSAttributedString(
                string: words,
                attributes: [ .font: font, .foregroundColor: colour, .paragraphStyle: style ]
            )
            .draw(in: box.offsetBy(dx: offset, dy: 0))
        }

        text.draw(in: box)
    }

    private static let title = UIFont.systemFont(ofSize: Design.Style.spineSize, weight: .medium, width: .compressed)

    private static let plate = UIFont.monospacedDigitSystemFont(ofSize: Design.Style.spineSize, weight: .medium)
}

/// Every colour a spine is printed in, and how the two shelves differ.
///
/// The figures are the spine's own rather than the palette's: what they are laid over is somebody else's
/// artwork, and a colour that reads on a card says nothing about one that reads on a picture.
struct SpineInk {
    let isDark: Bool

    /// Grey on a dark shelf, near-black on a light one. Writing printed onto a binding is never the
    /// brightest thing on it.
    var ink: UIColor { isDark ? .white.withAlphaComponent(0.58) : .black.withAlphaComponent(0.8) }

    /// How light a spine may get, and how dark. Drawn per channel, so a colour keeps its hue and gives
    /// up only what stood past the line.
    var limit: UIColor { UIColor(white: isDark ? 0.45 : 0.35, alpha: 1) }

    var saturation: CGFloat { isDark ? 1.35 : 1.7 }

    var brightness: CGFloat { isDark ? -0.18 : 0.14 }

    var wash: UIColor { isDark ? .black.withAlphaComponent(0.15) : .white.withAlphaComponent(0.06) }

    /// Settled against this spine's own scheme rather than the room's, since a press prints where
    /// there is no room to read.
    var bare: UIColor {
        UIColor(Design.Surface.fill)
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: isDark ? .dark : .light))
    }

    var head: UIColor { isDark ? .white.withAlphaComponent(0.3) : .black.withAlphaComponent(0.4) }

    var foot: UIColor { .black.withAlphaComponent(0.4) }

    var relief: UIColor { isDark ? .black.withAlphaComponent(0.6) : .black.withAlphaComponent(0.3) }

    var highlight: UIColor { isDark ? .white.withAlphaComponent(0.3) : .white.withAlphaComponent(0.85) }

    var plate: UIColor { isDark ? .black.withAlphaComponent(0.38) : .white.withAlphaComponent(0.28) }

    var plateEdge: UIColor { .black.withAlphaComponent(0.3) }

    /// The stops of the light across the board, from one edge to the other, which are the shelf's own
    /// and are shared with nothing else.
    ///
    /// The very edge of a spine turns away from the light altogether: a hard line rather than a fade,
    /// and thin, being the last two hundredths of the width on either side. The lit middle is wider on
    /// a light shelf, where that band is also the paper the writing sits on, since a narrow one leaves
    /// the ends of a long title out on the cover's own colour.
    var curve: [(UIColor, CGFloat)] {
        let edge = UIColor(Board.edge(isDark ? .dark : .light))
        let shade = UIColor(Board.shade(isDark ? .dark : .light))
        let sheen = UIColor.white.withAlphaComponent(isDark ? 0.13 : 0.32)
        let lit: (from: CGFloat, to: CGFloat) = isDark ? (0.337, 0.643) : (0.248, 0.752)
        let clearOf: (from: CGFloat, to: CGFloat) = isDark ? (0.14, 0.86) : (0.1, 0.9)

        // Each transparent stop is the colour it fades from, and there are two at each place: only the
        // alpha moves. A gradient run through one plain clear stop walks the shading through grey on
        // its way to white, which reads as a step beside the highlight rather than as light.
        return [
            (edge, 0), (shade, 0.05),
            (shade.withAlphaComponent(0), clearOf.from), (sheen.withAlphaComponent(0), clearOf.from),
            (sheen, lit.from), (sheen, lit.to),
            (sheen.withAlphaComponent(0), clearOf.to), (shade.withAlphaComponent(0), clearOf.to),
            (shade, 0.95), (edge, 1),
        ]
    }
}
