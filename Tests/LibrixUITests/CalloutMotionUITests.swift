//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import UIKit
import XCTest

/// How an aside comes and goes, measured frame by frame off the screen.
///
/// An animation cannot be read out of the code: what is written is a spring, and what matters is what
/// it does. So the screen is photographed while it runs and the card's painted extent measured in each
/// frame. Growing out of what it points at reads as sizes climbing from small; the bounce reads as a
/// frame wider than the one it settles at; going back in must show no such frame.
final class CalloutMotionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // Slowed right down: a screenshot takes longer to make than the animation runs for, so at its
        // own speed every frame caught is the last one.
        app.launchArguments = [ "-at-design-system", "YES", "-at-motion-scale", "14" ]
        app.launch()
    }

    func testAnAsideGrowsOutOfItsPointAndBouncesOnTheWayOut() throws {
        let opener = scrolledTo(app.buttons["catalog.callout.low"])
        let card = app.descendants(matching: .any)["catalog.callout.presented"]

        // Where it ends up, which is what every frame is measured against, and the patch of screen to
        // look at. Read once it has settled, when the card is certain to be there to ask.
        opener.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the aside never opened")
        Thread.sleep(forTimeInterval: 6)

        let frame = card.frame
        let field = frame.insetBy(dx: -60, dy: -60)

        app.buttons["callout.close"].tap()
        Thread.sleep(forTimeInterval: 4)

        // Nothing is open now, so this is the page the aside will be drawn over.
        // The bare page, which every frame is compared against.
        let bare = try XCTUnwrap(screen(), "no screenshot came back")

        // What it settles at, measured the same way every frame is: both read off the screen, since
        // what is painted carries a shadow the element's own frame knows nothing about.
        opener.tap()
        Thread.sleep(forTimeInterval: 6)

        let settled = try XCTUnwrap(
            measure(watch(count: 1), field: field, against: bare).first,
            "the settled aside could not be measured"
        )

        app.buttons["callout.close"].tap()
        Thread.sleep(forTimeInterval: 4)

        opener.tap()
        // Enough to run past the settle: the last frames should be sitting still at the end of it.
        let coming = watch(count: 22)

        Thread.sleep(forTimeInterval: 6)
        app.buttons["callout.close"].tap()

        let going = watch(count: 16)

        save(coming, named: "coming-out", field: field)
        save(going, named: "going-back", field: field)

        let out = measure(coming, field: field, against: bare)
        let back = measure(going, field: field, against: bare)

        report("coming out", out, settled: settled)
        report("going back", back, settled: settled)
        print(String(format: "CALLOUT-MOTION element w=%.0f h=%.0f", frame.width, frame.height))

        let first = try XCTUnwrap(out.first, "no frame was caught on the way out")
        XCTAssertLessThan(first.height, settled.height, "the aside was already full size in its first frame")
        XCTAssertGreaterThan(
            out.map(\.height).max() ?? 0,
            settled.height,
            "no frame overshot, so nothing bounced on the way out"
        )
        XCTAssertLessThanOrEqual(
            back.map(\.height).max() ?? 0,
            settled.height + 2,
            "a frame overshot on the way back, so it bounced where it should not have"
        )
    }

    /// A screenshot, and what it takes to read points off it.
    private struct Shot {
        let shot: XCUIScreenshot
        let reader: PixelReader
        let scale: CGFloat
    }

    private func screen() -> Shot? {
        let shot = XCUIScreen.main.screenshot()

        guard let image = shot.image.cgImage, let reader = PixelReader(image: image) else { return nil }

        return Shot(shot: shot, reader: reader, scale: CGFloat(image.width) / app.frame.width)
    }

    /// Photographs the screen as fast as it can be read, for about as long as an aside takes to move.
    private func watch(count: Int) -> [Shot] {
        (0 ..< count).compactMap { _ in screen() }
    }

    /// How much of the field each frame covers: everything in it that the bare page does not have.
    private func measure(_ frames: [Shot], field: CGRect, against bare: Shot) -> [CGRect] {
        frames.compactMap { frame in
            let scaled = CGRect(
                x: field.minX * frame.scale,
                y: field.minY * frame.scale,
                width: field.width * frame.scale,
                height: field.height * frame.scale
            )

            guard
                let box = frame.reader.bounds(differingFrom: bare.reader, tolerance: 12, inside: scaled)
            else { return CGRect.zero }

            return CGRect(
                x: box.minX / frame.scale,
                y: box.minY / frame.scale,
                width: box.width / frame.scale,
                height: box.height / frame.scale
            )
        }
    }

    /// Writes the pictures out where they can be looked at. Reports go in a folder git never sees.
    private func save(_ frames: [Shot], named: String, field: CGRect) {
        let folder = URL(fileURLWithPath: Self.reports).appendingPathComponent(named)

        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        for (index, frame) in frames.enumerated() {
            let file = folder.appendingPathComponent(String(format: "%02d.png", index))

            // Cropped to the field: a whole screen of catalogue around a small card says nothing.
            guard
                let whole = frame.shot.image.cgImage,
                let cropped = whole.cropping(to: CGRect(
                    x: max(0, field.minX * frame.scale),
                    y: max(0, field.minY * frame.scale),
                    width: min(field.width * frame.scale, CGFloat(whole.width)),
                    height: min(field.height * frame.scale, CGFloat(whole.height))
                ))
            else { continue }

            try? UIImage(cgImage: cropped).pngData()?.write(to: file)
        }
    }

    private static let reports = "/Users/alex/Programming/LonelyBytes/Librix/Fixtures/Reports/motion"

    private func report(_ title: String, _ boxes: [CGRect], settled: CGRect) {
        print(String(format: "CALLOUT-MOTION %@ (settled w=%.0f h=%.0f)", title, settled.width, settled.height))

        for (index, box) in boxes.enumerated() {
            print(String(format: "CALLOUT-MOTION   %2d  w=%6.1f  h=%6.1f", index, box.width, box.height))
        }
    }

    private func scrolledTo(_ element: XCUIElement) -> XCUIElement {
        for _ in 0 ..< 12 {
            if element.exists, element.isHittable { return element }

            app.swipeUp(velocity: .fast)
        }

        XCTFail("never came into view")
        return element
    }
}
