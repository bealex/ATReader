//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import XCTest

/// Where the bar for finding a passage stands, which is the one thing about it that kept going wrong.
///
/// The page turns the safe area down, so the overlay that carries the bar is measured against the
/// screen's own foot and SwiftUI lifts nothing: the keyboard has to be measured. Measuring it wrongly
/// looks exactly like measuring it rightly until someone opens a keyboard, hence this.
final class ReaderSearchUITests: XCTestCase {
    func testTheBarStandsJustAboveTheKeyboard() throws {
        let app = launch()
        let page = try openTheBook(in: app)

        showChrome(on: page, in: app)
        app.buttons["More"].tap()
        app.buttons["Find"].tap()

        let field = app.textFields["reader.search.field"]

        XCTAssertTrue(field.waitForExistence(timeout: 10), "the bar for finding a passage never showed")

        let keyboard = app.keyboards.firstMatch

        guard keyboard.waitForExistence(timeout: 10) else {
            throw XCTSkip("this simulator shows no software keyboard, so there is nothing to stand clear of")
        }

        // Settled, not arriving: the bar moves with the keyboard and both are animating.
        waitUntil("the keyboard stopped moving", within: 10) { [previous = keyboard.frame] in
            keyboard.frame == previous && keyboard.frame.height > 0
        }

        let gap = keyboard.frame.minY - field.frame.maxY

        XCTAssertTrue(
            gap > 0 && gap < Self.mostItMayStandOff,
            "the bar's foot is \(gap) above the keyboard: field \(field.frame), keyboard \(keyboard.frame)"
        )
    }

    /// The bar keeps a little air over the keyboard and no more. Anything past this reads as the bar
    /// having been put somewhere else entirely, which is what it kept doing.
    private static let mostItMayStandOff: CGFloat = 40

    private func showChrome(on page: XCUIElement, in app: XCUIApplication) {
        guard !app.buttons["More"].exists else { return }

        page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        _ = app.buttons["More"].waitForExistence(timeout: 5)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()

        app.launchArguments = [ "-at-ui-test-guest", "-firstBook.offered", "NO" ]
        app.launch()

        XCTAssertTrue(app.collectionViews["library.list"].waitForExistence(timeout: 30), "the library never showed")
        return app
    }

    private func openTheBook(in app: XCUIApplication) throws -> XCUIElement {
        let cover = app.collectionViews["library.list"].cells.firstMatch.buttons.firstMatch

        XCTAssertTrue(cover.waitForExistence(timeout: 30), "the shelf stood no book on its face")
        cover.tap()

        let page = app.descendants(matching: .any)["reader.page"]

        XCTAssertTrue(page.waitForExistence(timeout: 30), "the book never opened")
        waitUntil("drew the page", within: 30) { page.staticTexts.firstMatch.exists }
        return page
    }
}
