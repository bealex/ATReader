//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import XCTest

/// The book a fresh install opens with, and the reader's right to be rid of it.
///
/// `-firstBook.offered NO` puts the mark back, which is what a fresh install looks like to the app.
/// The book is bundled, so neither test needs an account or a network.
final class FirstBookUITests: XCTestCase {
    func testAFreshInstallOpensWithABookOnTheShelf() throws {
        let app = launch(asFreshInstall: true)

        XCTAssertTrue(shelved(in: app), "the shelf stayed empty")
    }

    func testABookDeletedStaysDeleted() throws {
        let app = launch(asFreshInstall: true)

        XCTAssertTrue(shelved(in: app), "the shelf stayed empty")

        let book = app.collectionViews["library.list"].cells.firstMatch.buttons.firstMatch

        book.press(forDuration: 1.2)

        let delete = app.buttons["Delete this book"]

        XCTAssertTrue(delete.waitForExistence(timeout: 10), "the book offered no way out of the library")
        delete.tap()

        XCTAssertTrue(emptied(in: app), "the book stayed on the shelf")

        // Launched as the app is every other time, so the mark it left behind is the one that counts.
        let again = launch(asFreshInstall: false)

        XCTAssertTrue(emptied(in: again), "the book came back")
    }

    private func launch(asFreshInstall fresh: Bool) -> XCUIApplication {
        let app = XCUIApplication()

        app.launchArguments = [ "-at-ui-test-guest" ] + (fresh ? [ "-firstBook.offered", "NO" ] : [])
        app.launch()

        XCTAssertTrue(app.collectionViews["library.list"].waitForExistence(timeout: 30), "the library never showed")

        return app
    }

    /// The book is read in behind the screen, so the shelf fills a moment after it opens.
    private func shelved(in app: XCUIApplication) -> Bool {
        app.collectionViews["library.list"].cells.firstMatch.waitForExistence(timeout: 30)
            && !app.staticTexts["Nothing here yet"].exists
    }

    private func emptied(in app: XCUIApplication) -> Bool {
        app.staticTexts["Nothing here yet"].waitForExistence(timeout: 20)
    }
}
