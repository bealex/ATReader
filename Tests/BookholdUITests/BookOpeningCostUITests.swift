//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import XCTest

/// Opens and shuts the bundled book at its start and part way in, by the close button and by a drag,
/// with `-at-opening-probe` on, so the app logs what every frame of each run cost.
final class BookOpeningCostUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [ "-at-ui-test-guest", "-firstBook.offered", "NO", "-at-opening-probe", "YES" ]
        app.launch()
    }

    func testOpeningAndShuttingCost() throws {
        let cover = app.collectionViews["library.list"].cells.firstMatch.buttons.firstMatch

        XCTAssertTrue(cover.waitForExistence(timeout: 30), "the shelf stood no book on its face")
        Thread.sleep(forTimeInterval: 2)

        for _ in 0 ..< 2 { openAndShut(cover, byDrag: false, turning: 0) }

        openAndShut(cover, byDrag: false, turning: 8)

        for round in 0 ..< 4 { openAndShut(cover, byDrag: round.isMultiple(of: 2), turning: 0) }
    }

    /// Photographs a book opened part way in, slowed down, so the back of the leaf can be looked at.
    func testTheBackOfTheLeaf() throws {
        app.terminate()
        app.launchArguments += [ "-at-motion-scale", "6" ]
        app.launch()

        let cover = app.collectionViews["library.list"].cells.firstMatch.buttons.firstMatch

        XCTAssertTrue(cover.waitForExistence(timeout: 30), "the shelf stood no book on its face")
        openAndShut(cover, byDrag: false, turning: 6)

        let done = expectation(description: "shot")

        DispatchQueue.global().async {
            for frame in 0 ..< 16 {
                let shot = XCUIScreen.main.screenshot().pngRepresentation
                let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("leaf")

                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try? shot.write(to: folder.appendingPathComponent(String(format: "%02d.png", frame)))
                Thread.sleep(forTimeInterval: 0.25)
            }

            done.fulfill()
        }

        cover.tap()
        wait(for: [ done ], timeout: 60)
    }

    private func openAndShut(_ cover: XCUIElement, byDrag: Bool, turning: Int) {
        let page = app.descendants(matching: .any)["reader.page"]

        cover.tap()
        waitUntil("opened", within: 30) { page.exists && page.staticTexts.firstMatch.exists }
        Thread.sleep(forTimeInterval: 1.5)

        for _ in 0 ..< turning {
            page.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 0.6)
        }

        if byDrag {
            page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
                .press(forDuration: 0.05, thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
        } else {
            page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

            let close = app.buttons["reader.close"]

            XCTAssertTrue(close.waitForExistence(timeout: 10), "the reader showed no way out")
            close.tap()
        }

        XCTAssertTrue(page.waitForNonExistence(timeout: 20), "the book stayed open")
        Thread.sleep(forTimeInterval: 1.5)
    }
}
