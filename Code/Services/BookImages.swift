//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import CoreGraphics
import ImageIO
import OSLog
import UIKit

/// The two colours a page is set in, and whether its pictures are held to them.
struct PagePalette: Equatable {
    var foreground: UIColor
    var background: UIColor
    /// Every picture is drawn in the page's own two colours, colour art included.
    var isMonochrome: Bool

    /// True where the page is set light on dark, which is what a colour picture is faded into.
    var isDark: Bool { Self.luminance(of: background) < 0.5 }

    /// The paler of the page's two colours, which is what the light parts of a picture land on.
    var lighter: UIColor {
        Self.luminance(of: foreground) > Self.luminance(of: background) ? foreground : background
    }

    /// The deeper of the two, which is what the dark parts land on.
    var darker: UIColor {
        Self.luminance(of: foreground) > Self.luminance(of: background) ? background : foreground
    }

    /// How bright a colour is, resolved against whatever light or dark the page is being drawn in.
    private static func luminance(of colour: UIColor) -> CGFloat {
        var reds: CGFloat = 0
        var greens: CGFloat = 0
        var blues: CGFloat = 0
        var alpha: CGFloat = 0

        guard
            colour.resolvedColor(with: .current).getRed(&reds, green: &greens, blue: &blues, alpha: &alpha)
        else { return 0 }

        return 0.299 * reds + 0.587 * greens + 0.114 * blues
    }
}

extension NSAttributedString.Key {
    /// The picture a block stands for, on a block that is a picture rather than text.
    static let pageImage = NSAttributedString.Key("ATPageImage")
}

/// One picture from a book, decoded once and ready for a page to draw.
///
/// A picture is either colour art, which the page shows as it is, or monochrome: line art, a scan,
/// anything grey. A monochrome picture is redrawn in the page's own two colours, so an illustration is
/// set in the same ink as the text around it rather than carrying its own paper onto the page. Which of
/// the two a picture is comes from its pixels, since nothing in the file says.
///
/// A picture the reader has chosen to see in monochrome takes that path whatever it is made of.
final class PageImage {
    enum Kind {
        /// Colour art, shown as it was drawn.
        case colour
        /// Line art, a scan, anything grey: drawn in the page's own two colours.
        case monochrome
    }

    /// The picture's own size, in pixels.
    let size: CGSize
    let kind: Kind

    /// The picture's own pixels. Only colour art keeps them.
    private let colour: CGImage?
    /// How dark each pixel is, white for black: what the page paints its deeper colour through.
    private let darkness: CGImage?

    fileprivate init(size: CGSize, kind: Kind, colour: CGImage?, darkness: CGImage?) {
        self.size = size
        self.kind = kind
        self.colour = colour
        self.darkness = darkness
    }

    /// How far a colour picture is faded on a dark page, so it doesn't glare beside the text.
    static let dimming: CGFloat = 0.82

    /// How large the picture is drawn in a column of a given measure.
    ///
    /// It takes the whole measure, but is never blown up past a pixel to the point: a small decoration
    /// stays small rather than turning into a blurred plate. A picture too deep for the page it lands on
    /// gives up width until it fits.
    func size(fitting measure: CGFloat, depth: CGFloat) -> CGSize {
        guard size.width > 0, size.height > 0, measure > 0, depth > 0 else { return .zero }

        var width = min(measure, size.width)
        var height = width * size.height / size.width

        if height > depth {
            height = depth
            width = height * size.width / size.height
        }

        return CGSize(width: width, height: height)
    }

    /// Draws the picture into a UIKit context, in the page's colours or its own.
    func draw(in rect: CGRect, palette: PagePalette, into drawing: CGContext) {
        drawing.saveGState()
        // CoreGraphics counts upwards and a UIKit context downwards, so a picture drawn straight into
        // one stands on its head.
        drawing.translateBy(x: rect.minX, y: rect.maxY)
        drawing.scaleBy(x: 1, y: -1)

        let target = CGRect(origin: .zero, size: rect.size)

        if let darkness, kind == .monochrome || palette.isMonochrome {
            // The picture keeps its own light and dark; only the two colours they land on change. The
            // pale colour is laid down whole and the deep one painted over it through the picture's own
            // shading, which is what turns a grey into a mixture of the two rather than one or other.
            drawing.setFillColor(palette.lighter.resolvedColor(with: .current).cgColor)
            drawing.fill(target)
            drawing.clip(to: target, mask: darkness)
            drawing.setFillColor(palette.darker.resolvedColor(with: .current).cgColor)
            drawing.fill(target)
        } else if let colour {
            drawing.setAlpha(palette.isDark ? Self.dimming : 1)
            drawing.draw(colour, in: target)
        }

        drawing.restoreGState()
    }
}

/// The pictures a book's chapters draw, read off the device once and kept.
///
/// Deciding what a picture is made of means looking at every pixel of it, so it happens once per
/// picture rather than on every re-pagination. Reading and decoding run away from the main actor and
/// hand back plain bytes; wrapping those in a `CGImage` costs nothing and happens here.
@MainActor
final class BookImages {
    static let shared = BookImages()

    private static let logger = Logger(subsystem: "com.lonelybytes.atreader", category: "images")

    /// The longest edge a picture is kept at, in pixels. Wider than any column this app draws, and the
    /// ceiling on what one picture costs in memory.
    nonisolated static let maximumPixelSize = 1600

    /// How coarsely a picture is sampled to work out what it is made of.
    private nonisolated static let sampleSize = 64

    /// How much of a picture may carry colour before it counts as colour art.
    private nonisolated static let colourShare: CGFloat = 0.02

    /// How far a pixel's channels may part before it counts as coloured rather than grey.
    private nonisolated static let colourDistance: CGFloat = 0.12

    private let cache = NSCache<NSString, PageImage>()
    /// Sources nothing on this device answers to, so a chapter full of them isn't looked up again on
    /// every re-pagination. A picture from the service is one of these: its bytes are not here.
    private var unresolved: Set<String> = []

    init() {
        cache.countLimit = 64
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    /// The pictures behind a chapter's sources, reading whichever aren't in hand yet.
    ///
    /// A source with no picture behind it is simply absent from the answer, and the block that named it
    /// is dropped rather than left as a gap on the page.
    func prepare(sources: [String]) async -> [String: PageImage] {
        var ready: [String: PageImage] = [:]
        var wanted: [String: URL] = [:]

        for source in Set(sources) {
            if let known = cache.object(forKey: source as NSString) {
                ready[source] = known
            } else if !unresolved.contains(source), let url = LocalBooks.imageURL(source: source) {
                wanted[source] = url
            } else {
                unresolved.insert(source)
            }
        }

        guard !wanted.isEmpty else { return ready }

        let read = await Task.detached(priority: .userInitiated) { Self.read(wanted) }.value

        for (source, url) in wanted {
            guard
                let ingredients = read[source],
                let picture = Self.picture(ingredients)
            else {
                Self.logger.debug("no picture at \(url.lastPathComponent, privacy: .public)")
                unresolved.insert(source)
                continue
            }

            cache.setObject(picture, forKey: source as NSString, cost: ingredients.cost)
            ready[source] = picture
        }

        return ready
    }

    /// A picture already in hand, read the same way as one off the device.
    ///
    /// A cover arrives decoded from ``CoverCache`` rather than as a file, and is small enough that
    /// reading it costs less than handing it to another actor would.
    func prepare(_ image: UIImage, key: String) -> PageImage? {
        if let known = cache.object(forKey: key as NSString) { return known }

        guard
            let decoded = image.cgImage,
            let ingredients = Self.read(decoded),
            let picture = Self.picture(ingredients)
        else { return nil }

        cache.setObject(picture, forKey: key as NSString, cost: ingredients.cost)
        return picture
    }

    // MARK: - Reading a picture off the device

    /// One picture pulled apart into what a page needs, in pieces that can cross an actor.
    private struct Ingredients: Sendable {
        var size: CGSize
        var width: Int
        var height: Int
        var kind: PageImage.Kind
        /// Premultiplied RGBA. Only colour art keeps it.
        var colour: Data?
        /// One byte a pixel, white where the picture is black.
        var darkness: Data

        var cost: Int { darkness.count + (colour?.count ?? 0) }
    }

    private nonisolated static func read(_ sources: [String: URL]) -> [String: Ingredients] {
        sources.reduce(into: [String: Ingredients]()) { result, entry in
            result[entry.key] = read(entry.value)
        }
    }

    private nonisolated static func read(_ url: URL) -> Ingredients? {
        guard
            let data = try? Data(contentsOf: url, options: .mappedIfSafe),
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        return read(decoded)
    }

    private nonisolated static func read(_ image: CGImage) -> Ingredients? {
        guard let raster = raster(of: image) else { return nil }

        let isColour = isColour(raster)

        return Ingredients(
            size: CGSize(width: image.width, height: image.height),
            width: raster.width,
            height: raster.height,
            kind: isColour ? .colour : .monochrome,
            colour: isColour ? raster.pixels : nil,
            darkness: darkness(raster)
        )
    }

    /// A picture as a buffer of pixels, which is what everything below reads.
    private struct Raster {
        var pixels: Data
        var width: Int
        var height: Int

        var count: Int { width * height }
    }

    /// The picture as premultiplied RGBA, shrunk to something a page can use.
    private nonisolated static func raster(of image: CGImage) -> Raster? {
        let longest = CGFloat(max(image.width, image.height))
        let scale = min(1, CGFloat(maximumPixelSize) / max(1, longest))
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        var pixels = Data(count: width * height * 4)

        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard
                let context = CGContext(
                    data: raw.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return false }

            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        return drawn ? Raster(pixels: pixels, width: width, height: height) : nil
    }

    /// One pixel read back, with the alpha divided out of it.
    ///
    /// The buffer is premultiplied, so a half-transparent black and a half-transparent white hold the
    /// same bytes until that is undone.
    private struct Tone {
        var luminance: CGFloat
        /// How far the pixel's channels stand apart, which is what makes it coloured rather than grey.
        var spread: CGFloat
        var alpha: CGFloat
    }

    private nonisolated static func tone(_ pixels: UnsafeRawBufferPointer, at index: Int) -> Tone {
        let alpha = CGFloat(pixels[index + 3]) / 255

        guard alpha > 0 else { return Tone(luminance: 0, spread: 0, alpha: 0) }

        let reds = CGFloat(pixels[index]) / 255 / alpha
        let greens = CGFloat(pixels[index + 1]) / 255 / alpha
        let blues = CGFloat(pixels[index + 2]) / 255 / alpha

        return Tone(
            luminance: min(1, 0.299 * reds + 0.587 * greens + 0.114 * blues),
            spread: max(reds, greens, blues) - min(reds, greens, blues),
            alpha: alpha
        )
    }

    // MARK: - What the picture is made of

    /// True where enough of the picture carries colour that redrawing it would throw something away.
    ///
    /// Sampled coarsely: a picture is one thing or the other all over, and a full pass over every pixel
    /// answers the same question at the cost of reading the whole book's art twice.
    private nonisolated static func isColour(_ raster: Raster) -> Bool {
        let width = raster.width
        let height = raster.height
        let step = max(1, max(width, height) / sampleSize)
        var opaque = 0
        var coloured = 0

        raster.pixels.withUnsafeBytes { pixels in
            for y in stride(from: 0, to: height, by: step) {
                for x in stride(from: 0, to: width, by: step) {
                    let tone = tone(pixels, at: (y * width + x) * 4)

                    guard tone.alpha > 0.5 else { continue }

                    opaque += 1

                    if tone.spread > colourDistance { coloured += 1 }
                }
            }
        }

        guard opaque > 0 else { return false }

        return CGFloat(coloured) / CGFloat(opaque) > colourShare
    }

    /// How dark each pixel is, as a grey picture the page paints its deeper colour through.
    ///
    /// The picture's own light and dark are kept: black is all the way dark and white is none of it, so
    /// an illustration reads the same way round whatever the page is set in. What is transparent counts
    /// as light, since the paper it was drawn on is what shows through there.
    private nonisolated static func darkness(_ raster: Raster) -> Data {
        var shading = Data(count: raster.count)

        shading.withUnsafeMutableBytes { output in
            raster.pixels.withUnsafeBytes { pixels in
                for index in 0 ..< raster.count {
                    let tone = tone(pixels, at: index * 4)

                    output[index] = UInt8(min(255, max(0, (1 - tone.luminance) * tone.alpha * 255)))
                }
            }
        }

        return shading
    }

    // MARK: - Bytes back into a picture

    private static func picture(_ ingredients: Ingredients) -> PageImage? {
        let darkness = image(ingredients.darkness, width: ingredients.width, height: ingredients.height, components: 1)
        let colour = ingredients.colour.flatMap {
            image($0, width: ingredients.width, height: ingredients.height, components: 4)
        }

        guard darkness != nil || colour != nil else { return nil }

        return PageImage(size: ingredients.size, kind: ingredients.kind, colour: colour, darkness: darkness)
    }

    /// Wraps a buffer as a picture. No decoding happens here: the bytes are already pixels.
    private static func image(_ bytes: Data, width: Int, height: Int, components: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: bytes as CFData) else { return nil }

        let isGrey = components == 1

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: components * 8,
            bytesPerRow: width * components,
            space: isGrey ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: isGrey ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
