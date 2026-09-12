//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import XCTest

/// Looks at what an aside is actually painted with, rather than at what it was asked to be painted with.
///
/// The arrow is drawn by the system as part of the presentation, and the card by the content inside it,
/// so the two can take their ground from different places and no amount of reading the code says which.
/// This reads the pixels.
final class CalloutBackgroundUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [ "-at-design-system", "YES" ]
        app.launch()
    }

    func testTheArrowIsPaintedWithTheSameGroundAsTheCard() throws {
        // The lower point opens its aside upwards, which puts the arrow along the bottom edge where a
        // column of pixels can walk out of the card and into it. That button is centred on the panel,
        // so it stands directly under the point the aside is hung on.
        let under = scrolledTo(app.buttons["catalog.callout.low"])

        under.tap()

        let card = app.descendants(matching: .any)["catalog.callout.presented"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the aside never opened")

        let shot = XCUIScreen.main.screenshot()
        let image = try XCTUnwrap(shot.image.cgImage)
        let scale = CGFloat(image.width) / app.frame.width
        let reader = try XCTUnwrap(PixelReader(image: image))

        let inside = try XCTUnwrap(reader.colour(atX: card.frame.midX * scale, y: card.frame.midY * scale))

        // Just outside the card's own edge, down the middle of the arrow. The arrow belongs to the
        // presentation rather than to the card, so this is where the two grounds show up as two.
        for step in stride(from: 2.0, through: 8.0, by: 3.0) {
            let point = CGPoint(x: under.frame.midX * scale, y: (card.frame.maxY + step) * scale)
            let outside = try XCTUnwrap(reader.colour(atX: point.x, y: point.y))

            XCTAssertLessThan(
                inside.distance(to: outside),
                12,
                "the arrow is not the ground the card stands on: card \(inside), \(Int(step)) below \(outside)"
            )
        }
    }

    private func scrolledTo(_ element: XCUIElement) -> XCUIElement {
        for _ in 0 ..< 20 {
            if element.exists, element.isHittable { return element }

            app.swipeUp()
        }

        XCTFail("never came into view")
        return element
    }
}

/// Reads single pixels out of a screenshot.
struct PixelReader {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init?(image: CGImage) {
        width = image.width
        height = image.height

        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue

        guard
            let context = CGContext(
                data: &buffer,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: info
            )
        else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = buffer
    }

    /// The box every pixel of a colour falls inside, or nothing where none of it is on screen.
    ///
    /// Stepped rather than walked pixel by pixel: this runs once a frame and a step of two points is
    /// finer than anything being measured.
    func bounds(of colour: Pixel, tolerance: Int) -> CGRect? {
        var left = width
        var right = -1
        var top = height
        var bottom = -1

        for row in stride(from: 0, to: height, by: 2) {
            for column in stride(from: 0, to: width, by: 2) {
                guard
                    let found = self.colour(atX: CGFloat(column), y: CGFloat(row)),
                    found.distance(to: colour) <= tolerance
                else { continue }

                left = min(left, column)
                right = max(right, column)
                top = min(top, row)
                bottom = max(bottom, row)
            }
        }

        guard right >= left, bottom >= top else { return nil }

        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// The box around everything inside a region that is not the colour given.
    ///
    /// Stepped rather than walked pixel by pixel: this runs once a frame and two points is finer than
    /// anything being measured.
    func bounds(differingFrom colour: Pixel, tolerance: Int, inside region: CGRect) -> CGRect? {
        var left = width
        var right = -1
        var top = height
        var bottom = -1

        let fromX = max(0, Int(region.minX))
        let toX = min(width, Int(region.maxX))
        let fromY = max(0, Int(region.minY))
        let toY = min(height, Int(region.maxY))

        for row in stride(from: fromY, to: toY, by: 2) {
            for column in stride(from: fromX, to: toX, by: 2) {
                guard
                    let found = self.colour(atX: CGFloat(column), y: CGFloat(row)),
                    found.distance(to: colour) > tolerance
                else { continue }

                left = min(left, column)
                right = max(right, column)
                top = min(top, row)
                bottom = max(bottom, row)
            }
        }

        guard right >= left, bottom >= top else { return nil }

        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// The box around everything inside a region that this picture has and another has not.
    ///
    /// Against a picture of the bare page rather than against one colour: a card whose ground is a
    /// shade of the page cannot be told from the page by its colour, but it can by its arrival.
    func bounds(differingFrom bare: PixelReader, tolerance: Int, inside region: CGRect) -> CGRect? {
        var left = width
        var right = -1
        var top = height
        var bottom = -1

        let fromX = max(0, Int(region.minX))
        let toX = min(width, Int(region.maxX))
        let fromY = max(0, Int(region.minY))
        let toY = min(height, Int(region.maxY))

        for row in stride(from: fromY, to: toY, by: 2) {
            for column in stride(from: fromX, to: toX, by: 2) {
                guard
                    let here = colour(atX: CGFloat(column), y: CGFloat(row)),
                    let there = bare.colour(atX: CGFloat(column), y: CGFloat(row)),
                    here.distance(to: there) > tolerance
                else { continue }

                left = min(left, column)
                right = max(right, column)
                top = min(top, row)
                bottom = max(bottom, row)
            }
        }

        guard right >= left, bottom >= top else { return nil }

        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    func colour(atX x: CGFloat, y: CGFloat) -> Pixel? {
        let column = Int(x)
        let row = Int(y)

        guard column >= 0, column < width, row >= 0, row < height else { return nil }

        let offset = (row * width + column) * 4
        return Pixel(red: bytes[offset], green: bytes[offset + 1], blue: bytes[offset + 2])
    }
}

/// One pixel of a screenshot.
struct Pixel: CustomStringConvertible, Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    var description: String { "\(red),\(green),\(blue)" }

    /// How far apart two colours stand, as the largest difference in any one channel.
    func distance(to other: Pixel) -> Int {
        max(
            abs(Int(red) - Int(other.red)),
            abs(Int(green) - Int(other.green)),
            abs(Int(blue) - Int(other.blue))
        )
    }
}
