//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import XCTest

/// An app closed on a book opens on it again, and one closed on the shelf opens on the shelf.
///
/// The bundled book, so none of it needs an account.
final class KeptBookUITests: XCTestCase {
    func testAnAppClosedOnABookOpensOnItsPageAndShutsOntoTheShelf() throws {
        var app = launch(fresh: true)
        let cover = app.collectionViews["library.list"].cells.firstMatch.buttons.firstMatch

        XCTAssertTrue(cover.waitForExistence(timeout: 30), "the shelf stood no book on its face")
        cover.tap()

        var page = try openPage(in: app)

        // Off the page the book opened on, whichever way it has pages to turn.
        let opened = place(in: app)

        page.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        sleep(2)

        if place(in: app) == opened { page.swipeRight(velocity: .fast) }

        waitUntil("turned the page") { self.place(in: app) != opened }

        // The place is written a moment after a turn.
        sleep(1)

        let stoppedAt = place(in: app)

        // Put away first, as an app is before it is closed: that is when the page's picture is taken,
        // and the next launch opens on it.
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.terminate()
        app = launch(fresh: false)
        page = try openPage(in: app)

        waitUntil("drew the page it stopped on") { self.place(in: app) == stoppedAt }
        XCTAssertEqual(place(in: app), stoppedAt, "the book came back on another page")

        page.swipeDown(velocity: .fast)

        XCTAssertTrue(page.waitForNonExistence(timeout: 5), "the book stayed open after a drag down the page")
        XCTAssertTrue(app.collectionViews["library.list"].exists, "shutting the book did not show the shelf")

        app.terminate()
        app = launch(fresh: false)

        XCTAssertFalse(
            app.descendants(matching: .any)["reader.page"].waitForExistence(timeout: 3),
            "an app closed on the shelf opened on a book"
        )
    }

    /// Dragged shut the moment it shows, before the shelf behind it can have stood its cover.
    func testABookOpenedAtLaunchShutsAtOnce() throws {
        var app = launch(fresh: true)
        let cover = app.collectionViews["library.list"].cells.firstMatch.buttons.firstMatch

        XCTAssertTrue(cover.waitForExistence(timeout: 30), "the shelf stood no book on its face")
        cover.tap()
        _ = try openPage(in: app)
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.terminate()

        app = XCUIApplication()
        app.launchArguments = [ "-at-ui-test-guest", "-at-restores-book", "YES" ]
        app.launch()

        let page = app.descendants(matching: .any)["reader.page"]

        XCTAssertTrue(page.waitForExistence(timeout: 30), "no book was open")
        page.swipeDown(velocity: .fast)

        XCTAssertTrue(page.waitForNonExistence(timeout: 5), "the book stayed open after a drag down the page")
    }

    /// A book the shelf doesn't hold has no cover to shut onto, and a drag down still shuts it.
    func testABookTheShelfDoesNotHoldShutsWithADragDown() throws {
        let app = XCUIApplication()

        app.launchArguments = [
            "-at-ui-test-guest", "-at-restores-book", "YES", "-firstBook.offered", "YES",
            "-openBook.workId", "424242", "-openBook.title", "Zzyx",
        ]
        app.launch()

        let list = app.collectionViews["library.list"]

        XCTAssertTrue(list.waitForExistence(timeout: 30), "the library never showed")
        waitUntil("opened the book over the shelf") { !list.isHittable }
        // Long enough for the shelf to have stood the cover, were there one.
        sleep(2)
        app.windows.firstMatch.swipeDown(velocity: .fast)

        waitUntil("shut the book", within: 5) { list.isHittable }
        XCTAssertTrue(list.isHittable, "the book stayed open after a drag down the page")
    }

    private func launch(fresh: Bool) -> XCUIApplication {
        let app = XCUIApplication()

        app.launchArguments =
            [ "-at-ui-test-guest", "-at-restores-book", "YES" ] + (fresh ? [ "-firstBook.offered", "NO" ] : [])
        app.launch()

        XCTAssertTrue(app.collectionViews["library.list"].waitForExistence(timeout: 30), "the library never showed")
        return app
    }

    private func openPage(in app: XCUIApplication) throws -> XCUIElement {
        let page = app.descendants(matching: .any)["reader.page"]

        XCTAssertTrue(page.waitForExistence(timeout: 30), "no book was open")
        waitUntil("drew the page", within: 30) { page.staticTexts.firstMatch.exists }
        return page
    }

    /// How long the page's own words run, which tells one page from another without quoting a book.
    ///
    /// The longest of what the page publishes, its running head and number being texts too. The number
    /// is no use here: it is counted against a length the book goes on estimating.
    private func place(in app: XCUIApplication) -> Int {
        let texts = app.descendants(matching: .any)["reader.page"].staticTexts.allElementsBoundByIndex

        return texts.map { $0.label.count }.max() ?? 0
    }
}
