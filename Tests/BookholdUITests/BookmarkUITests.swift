//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import XCTest

/// Marking a page, finding the mark under its chapter, and taking it off again.
///
/// The bundled book, so none of it needs an account.
final class BookmarkUITests: XCTestCase {
    func testAPageIsMarkedFoundInTheContentsAndCleared() throws {
        let app = launch()
        let page = try openTheBook(in: app)

        // A book opens on its title page, which carries none of a chapter's text and so can hold no
        // mark. The reading starts on the page after it.
        turnPage(on: page)
        showChrome(on: page, in: app)

        let add = app.buttons["Add bookmark"]

        XCTAssertTrue(add.waitForExistence(timeout: 10), "the reader offered no way to mark the page")
        add.tap()

        XCTAssertTrue(
            app.buttons["Remove bookmark"].waitForExistence(timeout: 5),
            "the page did not read as marked once it had been"
        )

        app.buttons["More"].tap()
        app.buttons["Contents"].tap()

        let mark = app.buttons["Bookmark"].firstMatch

        XCTAssertTrue(mark.waitForExistence(timeout: 10), "the mark never showed under its chapter")

        mark.swipeLeft()
        app.buttons["Remove"].firstMatch.tap()

        XCTAssertFalse(mark.waitForExistence(timeout: 2), "the mark stayed in the contents after it was taken off")
    }

    /// Turns one page forward, by a tap in the outer third the way a reader does.
    private func turnPage(on page: XCUIElement) {
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
    }

    /// The reader opens with its bar away, and the glyph the chapter list lives under is on that bar.
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
