//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import XCTest

/// The drags the reader's page answers, and the one it hands on.
///
/// A book is opened out of the cover it stands on, and the transition that grows it is closed by
/// dragging it back down. The page turns on sideways drags, so the two are told apart on the screen
/// rather than in the code. The book is the bundled one, so neither test needs an account.
final class ReaderSwipeUITests: XCTestCase {
    func testADragDownThePageClosesTheBook() throws {
        let app = launch()
        let page = try openTheBook(in: app)

        page.swipeDown(velocity: .fast)

        XCTAssertTrue(
            app.collectionViews["library.list"].waitForExistence(timeout: 5),
            "the book stayed open after a drag down the page"
        )
        // The reader puts the stack's bar away while it reads, and has to hand it back on the way out
        // however it left. Dragging the book shut is not the way the bar is used to being given back.
        XCTAssertTrue(
            app.navigationBars.firstMatch.waitForExistence(timeout: 5),
            "the library came back without its navigation bar"
        )
    }

    func testADragAcrossThePageTurnsIt() throws {
        let app = launch()
        let page = try openTheBook(in: app)
        let before = try words(on: page)

        page.swipeLeft(velocity: .fast)
        waitUntil("turned the page") { (try? words(on: page)) != before }

        XCTAssertTrue(page.exists, "a sideways drag closed the book instead of turning a page")
    }

    /// The drag the stack claims for itself, which on this screen turns back a page instead.
    func testADragInFromTheLeadingEdgeTurnsBack() throws {
        let app = launch()
        let page = try openTheBook(in: app)
        let opened = try words(on: page)

        page.swipeLeft(velocity: .fast)
        waitUntil("turned the page forward to begin with") { (try? words(on: page)) != opened }

        let edge = page.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))

        edge.press(forDuration: 0.05, thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)))
        waitUntil("turned back to the page it opened on") { (try? words(on: page)) == opened }

        XCTAssertTrue(page.exists, "a drag in from the edge closed the book")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()

        app.launchArguments = [ "-at-ui-test-guest", "-firstBook.offered", "NO" ]
        app.launch()

        XCTAssertTrue(app.collectionViews["library.list"].waitForExistence(timeout: 30), "the library never showed")
        return app
    }

    /// Opens the shelf's own book by its cover, which is the one way in that grows out of it.
    private func openTheBook(in app: XCUIApplication) throws -> XCUIElement {
        let cover = app.collectionViews["library.list"].cells.firstMatch.buttons.firstMatch

        XCTAssertTrue(cover.waitForExistence(timeout: 30), "the shelf stood no book on its face")
        cover.tap()

        let page = app.descendants(matching: .any)["reader.page"]

        XCTAssertTrue(page.waitForExistence(timeout: 30), "the book never opened")
        // The chapter is set before it is drawn, and the zoom has to settle: a drag during either is
        // not the page's. The page publishing its words is what says both are done.
        waitUntil("drew the page", within: 30) { page.staticTexts.firstMatch.exists }
        return page
    }

    /// How long the page's own words run, which is what says one page is not another.
    ///
    /// Drawn text is published as the page's accessibility label, and the length of it is enough to
    /// tell two pages apart without a test holding a line of anybody's book.
    private func words(on page: XCUIElement) throws -> Int {
        let text = page.staticTexts.firstMatch

        XCTAssertTrue(text.waitForExistence(timeout: 10), "the page published no text")
        return text.label.count
    }
}
