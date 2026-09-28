//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import XCTest

/// Photographs the bundled book being opened from its cover and shut again, with the motion slowed so
/// every frame lands.
final class BookOpeningMotionUITests: XCTestCase {
    private var app: XCUIApplication!

    private static let slowdown = 8.0

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-at-ui-test-guest", "-firstBook.offered", "NO", "-at-motion-scale", "\(Self.slowdown)",
        ]
        app.launch()
    }

    func testOpeningAndShuttingABook() throws {
        let cover = app.collectionViews["library.list"].cells.firstMatch.buttons.firstMatch

        XCTAssertTrue(cover.waitForExistence(timeout: 30), "the shelf stood no book on its face")
        Thread.sleep(forTimeInterval: 2)
        try shoot("00-shelf")

        shooting("open", while: { cover.tap() })

        let page = app.descendants(matching: .any)["reader.page"]

        XCTAssertTrue(page.waitForExistence(timeout: 30), "the book never opened")
        Thread.sleep(forTimeInterval: 4)
        try shoot("30-open")
        waitUntil("drew the page", within: 30) { page.staticTexts.firstMatch.exists }

        // The way out sits with the chrome, which a tap in the middle of the page brings up.
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let close = app.buttons["reader.close"]

        XCTAssertTrue(close.waitForExistence(timeout: 10), "the reader showed no way out")
        shooting("shut", while: { close.tap() })

        XCTAssertTrue(page.waitForNonExistence(timeout: 20), "the book stayed open")
        Thread.sleep(forTimeInterval: 2)
        try shoot("60-shelf")

        // Shut by a drag, let go half way so it runs on by itself.
        cover.tap()
        waitUntil("opened again", within: 30) { page.exists && page.staticTexts.firstMatch.exists }
        // The page is there from the first frame of the opening, and a touch during it goes unheard.
        Thread.sleep(forTimeInterval: Self.slowdown)

        let from = page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))

        shooting("drag", while: {
            from.press(forDuration: 0.05, thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
        })

        // The shelf stays underneath a book over it, so what says the book shut is the page going.
        XCTAssertTrue(page.waitForNonExistence(timeout: 20), "the book stayed open after a drag down the page")
        Thread.sleep(forTimeInterval: 2)
        try shoot("99-shelf")
    }

    /// Photographed from a thread of its own: a tap waits for the animation it starts.
    private func shooting(_ name: String, while act: () -> Void) {
        let done = expectation(description: name)

        DispatchQueue.global().async {
            for frame in 0 ..< 24 {
                try? self.shoot(String(format: "%@-%02d", name, frame))
                Thread.sleep(forTimeInterval: 0.2)
            }

            done.fulfill()
        }

        act()
        wait(for: [ done ], timeout: 120)
    }

    private func shoot(_ name: String) throws {
        let reports = ProcessInfo.processInfo.environment["AT_REPORTS"] ?? NSTemporaryDirectory()
        let folder = URL(fileURLWithPath: reports).appendingPathComponent("opening")

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try XCUIScreen.main.screenshot().pngRepresentation
            .write(to: folder.appendingPathComponent("\(name).png"))
    }
}
