//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import UIKit
import XCTest

/// Photographs a book being put away, frame by frame, with the motion slowed so every frame lands.
final class PutAwayMotionUITests: XCTestCase {
    private var app: XCUIApplication!

    private static let slowdown = 8.0

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [ "-at-design-system", "YES", "-at-motion-scale", "\(Self.slowdown)" ]
        app.launch()
    }

    func testPuttingABookAway() throws {
        app.segmentedControls["catalog.segment"].buttons["Motion"].tap()

        let shelf = app.descendants(matching: .any).matching(identifier: "catalog.putaway").element(boundBy: 0)
        XCTAssertTrue(shelf.waitForExistence(timeout: 20), "the catalogue has no put-away specimen")

        // Well up the screen rather than merely on it: what is being watched is the row below the
        // book as well as the book.
        while shelf.frame.minY > app.frame.height * 0.35 { app.swipeUp() }

        Thread.sleep(forTimeInterval: 3)

        let cover = shelf.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@",
            "Title of the book"
        )).element(boundBy: 0)
        XCTAssertTrue(cover.waitForExistence(timeout: 10), "no book stands out on the specimen")

        try shoot("00-before")

        cover.press(forDuration: 1)
        Thread.sleep(forTimeInterval: 1)
        try shoot("01-menu")

        // Photographed from a thread of its own: tapping waits for the animation it starts, so a run
        // that shoots after the tap only ever sees the end of it.
        let shooting = expectation(description: "frames")

        DispatchQueue.global().async {
            for frame in 0 ..< 30 {
                try? self.shoot(String(format: "%02d-turn", frame + 2))
                Thread.sleep(forTimeInterval: 0.05)
            }

            shooting.fulfill()
        }

        app.buttons["Put the book away"].tap()
        wait(for: [ shooting ], timeout: 60)

        try shoot("40-after")
    }

    private func shoot(_ name: String) throws {
        let reports = ProcessInfo.processInfo.environment["AT_REPORTS"] ?? NSTemporaryDirectory()
        let folder = URL(fileURLWithPath: reports).appendingPathComponent("putaway")

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try XCUIScreen.main.screenshot().pngRepresentation
            .write(to: folder.appendingPathComponent("\(name).png"))
    }
}
