//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import XCTest

/// Whether an author's name pinned under the navigation bar reads as part of the bar.
///
/// Runs on the invented library, so it needs no account. The screenshot goes to `Fixtures/Reports/shelf`,
/// and a strip of bar and a strip of header just under it have to come out the same colour.
final class HeaderMaterialUITests: XCTestCase {
    func testAPinnedNameMatchesTheBarAboveIt() throws {
        let app = try launchDemoLibrary()
        let list = app.collectionViews["library.list"]

        // Held before letting go, so the list stops where it was dragged instead of coasting on.
        list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(
                forDuration: 0.05,
                thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                withVelocity: .slow,
                thenHoldForDuration: 0.6
            )
        Thread.sleep(forTimeInterval: 1.5)

        let bar = app.navigationBars.firstMatch.frame
        let shot = XCUIScreen.main.screenshot()
        let image = try XCTUnwrap(shot.image.cgImage, "no screenshot came back")
        let scale = CGFloat(image.width) / shot.image.size.width

        // A column clear of the name and of the bar's buttons, just above the bar's foot and just below it.
        let barStrip = CGRect(x: 6, y: bar.maxY - 12, width: 12, height: 9)
        let headerStrip = CGRect(x: 6, y: bar.maxY + 3, width: 12, height: 9)

        let barColour = try XCTUnwrap(Self.average(of: barStrip, in: image, scale: scale))
        let headerColour = try XCTUnwrap(Self.average(of: headerStrip, in: image, scale: scale))

        try report(shot, named: "pinned.png")
        print("HEADER-MATERIAL bar \(barColour) header \(headerColour)")

        for (bar, header) in zip(barColour, headerColour) {
            XCTAssertLessThanOrEqual(abs(bar - header), Self.tolerance, "the pinned name stands on another ground than the bar")
        }
    }

    /// How far apart two channels may be and still read as one ground, out of 255.
    private static let tolerance = 8

    /// The average of a patch of the screen, as red, green and blue out of 255.
    private static func average(of patch: CGRect, in image: CGImage, scale: CGFloat) -> [Int]? {
        let box = CGRect(x: patch.minX * scale, y: patch.minY * scale, width: patch.width * scale, height: patch.height * scale)

        guard
            let cropped = image.cropping(to: box.integral),
            let context = CGContext(
                data: nil,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }

        context.interpolationQuality = .medium
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        guard let pixel = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

        return [ Int(pixel[0]), Int(pixel[1]), Int(pixel[2]) ]
    }
}
