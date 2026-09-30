//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import CryptoKit
import UIKit

/// A cover for a book that brought none: a two-colour gradient chosen by the book, its title set in the
/// middle, and the format it came in marked at the foot.
///
/// The colours come from the book's fingerprint, so the same book always gets the same cover and a
/// corrected file keeps it.
enum DrawnCover {
    /// The cover as JPEG bytes, the way a file's own cover arrives.
    static func draw(title: String, format: String, seed: String) -> Data? {
        let hues = hues(for: seed)
        let rendering = UIGraphicsImageRendererFormat()

        rendering.scale = 1
        rendering.opaque = true

        let image = UIGraphicsImageRenderer(size: size, format: rendering).image { context in
            gradient(hues, in: context.cgContext)
            set(title, in: titleBox)
            mark(format.uppercased(), in: context.cgContext)
        }

        return image.jpegData(compressionQuality: quality)
    }

    /// Two hues a little apart, both picked from the seed's bytes.
    static func hues(for seed: String) -> (CGFloat, CGFloat) {
        let bytes = Array(SHA256.hash(data: Data(seed.utf8)))
        let first = CGFloat(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / CGFloat(UInt16.max)
        let apart = hueSpread.lowerBound + CGFloat(bytes[2]) / 255 * (hueSpread.upperBound - hueSpread.lowerBound)

        return (first, (first + apart).truncatingRemainder(dividingBy: 1))
    }

    private static func gradient(_ hues: (CGFloat, CGFloat), in context: CGContext) {
        let colours = [
            UIColor(hue: hues.0, saturation: saturation, brightness: brightness.upperBound, alpha: 1).cgColor,
            UIColor(hue: hues.1, saturation: saturation, brightness: brightness.lowerBound, alpha: 1).cgColor,
        ]

        guard
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colours as CFArray,
                locations: [ 0, 1 ]
            )
        else { return }

        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
    }

    /// The title, as large as fits the box, centred in it both ways.
    private static func set(_ title: String, in box: CGRect) {
        var fontSize = largestTitle
        var text = titled(title, size: fontSize)
        var height = text.boundingRect(with: box.size, options: .usesLineFragmentOrigin, context: nil).height

        while height > box.height || !fitsWords(title, size: fontSize, width: box.width), fontSize > smallestTitle {
            fontSize -= 2
            text = titled(title, size: fontSize)
            height = text.boundingRect(with: box.size, options: .usesLineFragmentOrigin, context: nil).height
        }

        text.draw(
            with: CGRect(x: box.minX, y: box.midY - height / 2, width: box.width, height: height),
            options: .usesLineFragmentOrigin,
            context: nil
        )
    }

    /// True where no single word is wider than the box, which would break it mid-word.
    private static func fitsWords(_ title: String, size: CGFloat, width: CGFloat) -> Bool {
        let font = titleFont(size)

        return title.split(separator: " ").allSatisfy {
            (String($0) as NSString).size(withAttributes: [ .font: font ]).width <= width
        }
    }

    private static func titled(_ title: String, size: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()

        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping

        let shadow = NSShadow()

        shadow.shadowColor = UIColor.black.withAlphaComponent(shade)
        shadow.shadowOffset = CGSize(width: 0, height: size / 20)
        shadow.shadowBlurRadius = size / 8

        return NSAttributedString(
            string: title,
            attributes: [
                .font: titleFont(size),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph,
                .shadow: shadow,
            ]
        )
    }

    private static func titleFont(_ size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .bold)

        return base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? base
    }

    /// The format's name in a rounded frame, standing at the foot of the cover.
    private static func mark(_ name: String, in context: CGContext) {
        let base = UIFont.systemFont(ofSize: markSize, weight: .semibold)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: markSize) } ?? base
        let text = NSAttributedString(
            string: name,
            attributes: [ .font: font, .foregroundColor: UIColor.white, .kern: markSize / 8 ]
        )
        let measured = text.size()
        let frame = CGRect(
            x: (size.width - measured.width) / 2 - markSize * 0.6,
            y: size.height * markLine - measured.height / 2 - markSize * 0.25,
            width: measured.width + markSize * 1.2,
            height: measured.height + markSize * 0.5
        )

        context.setStrokeColor(UIColor.white.withAlphaComponent(markAlpha).cgColor)
        context.setLineWidth(markSize / 12)
        context.addPath(UIBezierPath(roundedRect: frame, cornerRadius: frame.height / 2).cgPath)
        context.strokePath()
        text.draw(at: CGPoint(x: frame.midX - measured.width / 2, y: frame.midY - measured.height / 2))
    }

    /// A book's shape, at the size the largest cover on a screen is drawn.
    private static let size = CGSize(width: coverWidth, height: coverWidth * 3 / 2)
    private static let coverWidth: CGFloat = 800
    private static var titleBox: CGRect {
        CGRect(x: size.width * 0.12, y: size.height * 0.12, width: size.width * 0.76, height: size.height * 0.62)
    }

    private static let largestTitle: CGFloat = 104
    private static let smallestTitle: CGFloat = 36
    private static let markSize: CGFloat = 36
    /// How far down the cover the format's mark stands.
    private static let markLine: CGFloat = 0.88
    private static let markAlpha: CGFloat = 0.8
    private static let shade: CGFloat = 0.25
    private static let hueSpread: ClosedRange<CGFloat> = 0.06 ... 0.18
    private static let saturation: CGFloat = 0.55
    private static let brightness: ClosedRange<CGFloat> = 0.45 ... 0.72
    private static let quality: CGFloat = 0.9
}
