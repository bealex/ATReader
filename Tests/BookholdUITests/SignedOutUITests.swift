//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import XCTest

/// What the app does for a reader who has never signed in.
///
/// The library reads books of their own, so an account is something to offer rather than to demand at
/// the door. These are easy to lose: one line in `RootScreen` puts the sign-in screen back in front of
/// everyone.
final class SignedOutUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launched() -> XCUIApplication {
        let app = XCUIApplication()

        app.launchArguments = [ "-at-ui-test-signed-out" ]
        app.launch()
        return app
    }

    func testOpensOnTheLibraryRatherThanTheSignInScreen() {
        let app = launched()

        XCTAssertTrue(app.waitForTabs(named: "Library"), "never reached the tabs")
        XCTAssertFalse(app.textFields["login.field"].exists, "the sign-in screen stood in the way")
    }

    /// The shelf carries whatever was imported, and says nothing about an account nobody claimed.
    func testRaisesNoErrorAboutAnAccountNobodyClaimed() {
        let app = launched()

        XCTAssertTrue(app.waitForTabs(named: "Library"), "never reached the tabs")
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 5), "an error stood over the shelf")
    }

    func testOffersTheWayToAddBooksWithoutAnAccount() {
        let app = launched()

        XCTAssertTrue(app.buttons["library.add"].waitForExistence(timeout: 30), "no way to add a book")
    }

    func testOffersSigningInFromTheProfile() {
        let app = launched()

        XCTAssertTrue(app.waitForTabs(named: "Profile"), "never reached the tabs")
        app.tab("Profile").tap()

        XCTAssertTrue(app.buttons["profile.signIn"].waitForExistence(timeout: 20), "the profile offered no way in")
    }
}
