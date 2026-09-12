//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import XCTest

/// What a book looks like while its menu is open.
///
/// A menu lifts what it was called on inside a rounded box of the system's own, which on a spine a few
/// points wide comes out as a lozenge. The book hands the menu its own shape instead. The screenshot
/// goes to `Fixtures/Reports/shelf`.
final class SpineMenuUITests: XCTestCase {
    func testAMenuOnASpineLiftsItOnItsOwnShape() throws {
        let app = try launchDemoLibrary()
        // A spine names its volume; a volume nobody holds says it isn't there.
        let spine = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH 'Volume' AND NOT (label CONTAINS 'not in your library')"))
            .firstMatch

        XCTAssertTrue(spine.waitForExistence(timeout: 10), "the shelf stood no book on its edge")

        spine.press(forDuration: 1.2)

        XCTAssertTrue(app.buttons["Read the book"].waitForExistence(timeout: 10), "the menu never opened")
        Thread.sleep(forTimeInterval: 1)

        try report(XCUIScreen.main.screenshot(), named: "menu.png")
    }

    func testAMenuOnACoverLiftsItOnTheBoardsOwnShape() throws {
        let app = try launchDemoLibrary()
        // Inside a card rather than on it, since an author's name is a button of its own; and a cover
        // names only its book, where a spine leads with its volume.
        let cover = app.collectionViews["library.list"].cells.element(boundBy: 0).buttons
            .matching(NSPredicate(format: "NOT (label BEGINSWITH 'Volume')"))
            .firstMatch

        XCTAssertTrue(cover.waitForExistence(timeout: 10), "the shelf stood no book on its face")

        cover.press(forDuration: 1.2)

        XCTAssertTrue(app.buttons["Read the book"].waitForExistence(timeout: 10), "the menu never opened")
        Thread.sleep(forTimeInterval: 1)

        try report(XCUIScreen.main.screenshot(), named: "menu-cover.png")
    }
}
