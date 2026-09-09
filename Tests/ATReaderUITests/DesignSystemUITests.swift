//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import XCTest

/// Drives the catalogue, which draws every component from the tokens themselves.
///
/// The catalogue opens straight from launch, so nothing here needs an account or a book. What it is
/// for is the components that only misbehave once something else is sizing them.
final class DesignSystemUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [ "-at-design-system", "YES" ]
        app.launch()
    }

    /// An aside in the column, where it is handed a width and almost any layout would look right.
    func testACalloutInAColumnRunsToSeveralLines() {
        let callout = scrolledTo(app.descendants(matching: .any)["catalog.callout"])

        XCTAssertGreaterThan(callout.frame.width, 200, "an aside collapsed to something too narrow to read")
        XCTAssertGreaterThan(callout.frame.height, 60, "an aside collapsed to a single line")
    }

    /// An aside offers a way out of itself, for a reader who would rather not guess where "outside" is.
    func testTheCloseButtonPutsAnAsideAway() {
        scrolledTo(app.buttons["catalog.callout.low"]).tap()

        let card = app.descendants(matching: .any)["catalog.callout.presented"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "the aside never opened")

        app.buttons["callout.close"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5), "the aside stayed open")
    }

    /// The catalogue is one long column, and a specimen below the fold has to be scrolled into reach.
    private func scrolledTo(_ element: XCUIElement) -> XCUIElement {
        for _ in 0 ..< 12 {
            if element.exists, element.isHittable { return element }

            app.swipeUp(velocity: .fast)
        }

        XCTFail("\(element) never came into view")
        return element
    }
}
