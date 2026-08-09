//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import XCTest

/// Covers the signed-in screens. Needs a token in `AT_TEST_TOKEN`; skipped without one.
final class LibraryUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launchSignedIn() throws {
        guard let token = ProcessInfo.processInfo.environment["AT_TEST_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Set AT_TEST_TOKEN to run the signed-in library tests.")
        }

        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [ "-at-ui-test-token", token ]
        app.launch()
    }

    func testLibraryListsTheReadersBooks() throws {
        try launchSignedIn()

        XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: 30), "never reached the tabs")

        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 30), "library list never rendered")

        // Either the reader has books, or the empty state explains why not — both are valid.
        let hasBooks = app.collectionViews.cells.count > 0
        let emptyState = app.staticTexts["Nothing here yet"].exists
        XCTAssertTrue(hasBooks || emptyState, "library showed neither books nor an empty state")
    }

    func testShelfFilterIsAvailable() throws {
        try launchSignedIn()

        XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: 30))

        let shelfButton = app.buttons["Choose a shelf"]
        XCTAssertTrue(shelfButton.waitForExistence(timeout: 20), "shelf filter missing")
        shelfButton.tap()

        XCTAssertTrue(app.buttons["All books"].waitForExistence(timeout: 10), "shelf menu did not open")
    }

    func testProfileShowsTheSignedInReaderAndCanSignOut() throws {
        try launchSignedIn()

        let profileTab = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 30))
        profileTab.tap()

        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 15))

        app.buttons["profile.signOut"].tap()
        app.buttons["Yes, sign out"].tap()

        XCTAssertTrue(
            app.buttons["login.submit"].waitForExistence(timeout: 20),
            "signing out did not return to the sign-in screen"
        )
    }
}
