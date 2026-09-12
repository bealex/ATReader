//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import XCTest

/// Covers the sign-in screen, including the two-factor step the service asks for on protected accounts.
///
/// Credentials come from the environment so none are ever committed:
/// `AT_TEST_LOGIN`, `AT_TEST_PASSWORD` and, for the full run, `AT_TEST_CODE`.
final class LoginUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testSubmitStaysDisabledUntilBothFieldsAreFilled() {
        let submit = app.buttons["login.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 15), "sign-in screen never appeared")
        XCTAssertFalse(submit.isEnabled, "submit should start disabled")

        let login = app.textFields["login.field"]
        login.tap()
        login.typeText("someone@example.com")
        XCTAssertFalse(submit.isEnabled, "submit should stay disabled without a password")

        let password = app.secureTextFields["login.password"]
        password.tap()
        password.typeText("placeholder")
        XCTAssertTrue(submit.isEnabled, "submit should enable once both fields are filled")
    }

    func testWrongPasswordShowsTheServiceMessage() {
        signIn(login: "no-such-account@example.invalid", password: "definitely-wrong")

        let error = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'sign-in error' OR label CONTAINS[c] 'couldn’t sign in'")
        )
        XCTAssertTrue(error.firstMatch.waitForExistence(timeout: 30), "no error surfaced for bad credentials")
    }

    /// Signs in for real. Skipped unless credentials are provided, so CI without secrets stays green.
    func testRealSignInReachesLibraryOrTwoFactor() throws {
        let environment = ProcessInfo.processInfo.environment

        guard
            let login = environment["AT_TEST_LOGIN"],
            let password = environment["AT_TEST_PASSWORD"]
        else {
            throw XCTSkip("Set AT_TEST_LOGIN and AT_TEST_PASSWORD to run the live sign-in test.")
        }

        signIn(login: login, password: password)

        let codeField = app.textFields["login.code"]
        let libraryTab = app.tabBars.buttons["Library"]

        // The account either signs straight in or asks for a second factor.
        let reachedEither = codeField.waitForExistence(timeout: 40) || libraryTab.waitForExistence(timeout: 5)
        XCTAssertTrue(reachedEither, "sign-in neither completed nor asked for a code")

        guard codeField.exists else { return }

        guard let code = environment["AT_TEST_CODE"], !code.isEmpty else {
            throw XCTSkip("Two-factor challenge reached. Set AT_TEST_CODE to finish the sign-in.")
        }

        codeField.tap()
        codeField.typeText(code)
        app.buttons["login.submit"].tap()

        XCTAssertTrue(libraryTab.waitForExistence(timeout: 40), "code was accepted but the library never appeared")
    }

    private func signIn(login: String, password: String) {
        let loginField = app.textFields["login.field"]
        XCTAssertTrue(loginField.waitForExistence(timeout: 15), "sign-in screen never appeared")
        loginField.tap()
        loginField.typeText(login)

        let passwordField = app.secureTextFields["login.password"]
        passwordField.tap()
        passwordField.typeText(password)

        app.buttons["login.submit"].tap()
    }
}
