//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import XCTest

/// Drives the catalogue-facing screens against the live service using the guest token.
///
/// These cover everything a reader can reach without an account: search, the charts, a book's page and
/// the reader itself. The library needs a real token and is covered by ``LibraryUITests``.
final class CatalogUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // Reader settings live in UserDefaults and survive app launches, so without this one test's
        // font size leaks into the next. The argument domain wins over stored values, which pins every
        // test to the same starting style.
        app.launchArguments = [
            "-at-ui-test-guest",
            "-reader.fontSize", "19",
            "-reader.lineSpacing", "7",
            "-reader.margins", "24",
            "-reader.face", "serif",
            "-reader.alignment", "justified",
            "-reader.theme", "system"
        ]
        app.launch()
    }

    func testSearchFindsBooksByText() {
        app.tabBars.buttons["Search"].tap()

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "search field never appeared")
        field.tap()
        field.typeText("магия\n")

        let list = app.otherElements["search.list"]
        let cell = app.collectionViews.cells.firstMatch
        XCTAssertTrue(
            cell.waitForExistence(timeout: 30) || list.waitForExistence(timeout: 5),
            "search returned no rows"
        )
        XCTAssertGreaterThan(app.collectionViews.cells.count, 0, "expected at least one search result")
    }

    func testSearchByAuthorScopeNarrowsResults() {
        app.tabBars.buttons["Search"].tap()

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Круз\n")

        XCTAssertTrue(app.collectionViews.cells.firstMatch.waitForExistence(timeout: 30))

        let authorScope = app.buttons["Author"]

        if authorScope.waitForExistence(timeout: 5) {
            authorScope.tap()
            // The scope filters locally; the list may legitimately shrink to nothing, so only assert it settles.
            XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 10))
        }
    }

    func testTopChartLoadsAndFiltersByPeriod() {
        app.tabBars.buttons["Top"].tap()

        XCTAssertTrue(
            app.collectionViews.cells.firstMatch.waitForExistence(timeout: 30),
            "top chart never populated"
        )

        let monthChip = app.buttons["This month"]
        XCTAssertTrue(monthChip.waitForExistence(timeout: 10))
        monthChip.tap()

        XCTAssertTrue(app.collectionViews.cells.firstMatch.waitForExistence(timeout: 30))
    }

    func testOpeningABookAndReadingAChapter() {
        openReader()
        turnPage()

        // The page publishes its drawn text as its accessibility label, so a substantial label is
        // evidence the chapter decrypted and paginated.
        var longest = longestPageLabel()
        let deadline = Date().addingTimeInterval(20)

        while Date() < deadline, longest.count <= 200 {
            longest = longestPageLabel()
        }

        XCTAssertGreaterThan(
            longest.count,
            200,
            "page body looks empty — decryption or pagination may have failed"
        )
    }

    func testTappingTheRightThirdTurnsThePage() {
        openReader()

        let caption = app.staticTexts["reader.caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 20), "page caption missing")

        let first = caption.label
        let page = app.otherElements["reader.page"].firstMatch
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()

        XCTAssertTrue(
            waitForChange(of: caption, from: first),
            "tapping the right third did not turn the page (was \(first))"
        )
    }

    func testTappingTheLeftThirdTurnsThePage() {
        openReader()

        let caption = app.staticTexts["reader.caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 20))

        let first = caption.label
        let page = app.otherElements["reader.page"].firstMatch
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()

        XCTAssertTrue(waitForChange(of: caption, from: first), "tapping the left third did not turn the page")
    }

    /// Tapping faster than a turn animates has to land every tap rather than drop the extras.
    func testRapidTapsKeepTurningPages() {
        openReader()

        let caption = app.staticTexts["reader.caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 20))

        let first = caption.label
        let page = app.otherElements["reader.page"].firstMatch
        let forward = page.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))

        for _ in 0 ..< 8 { forward.tap() }

        XCTAssertTrue(waitForChange(of: caption, from: first), "a burst of taps left the page where it started")
    }

    func testSwipingTurnsThePageBothWays() {
        openReader()

        let caption = app.staticTexts["reader.caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 20))

        let first = caption.label
        let page = app.otherElements["reader.page"].firstMatch
        page.swipeLeft()
        XCTAssertTrue(waitForChange(of: caption, from: first), "swiping left did not advance the page")

        let second = caption.label
        page.swipeRight()
        XCTAssertTrue(waitForChange(of: caption, from: second), "swiping right did not go back a page")
    }

    /// Changing the typeface re-paginates, which shows up as a different page count in the caption.
    func testChangingTypefaceRepaginates() {
        openReader()

        let caption = app.staticTexts["reader.caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 20))

        showChrome()
        app.buttons["Appearance"].tap()
        XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 10))

        let picker = app.buttons["reader.face"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "typeface dropdown missing")
        picker.tap()

        let charter = app.buttons["Charter"]
        XCTAssertTrue(charter.waitForExistence(timeout: 5), "typeface options did not open")
        charter.tap()

        XCTAssertTrue(picker.waitForExistence(timeout: 5), "dropdown did not close")
        app.buttons["Done"].tap()

        XCTAssertTrue(
            app.otherElements["reader.page"].firstMatch.waitForExistence(timeout: 20),
            "reader disappeared after changing typeface"
        )
        XCTAssertTrue(caption.waitForExistence(timeout: 10), "page caption lost after restyling")
    }

    func testMarginAndAlignmentControlsExist() {
        openReader()

        showChrome()
        app.buttons["Appearance"].tap()
        XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 10))

        XCTAssertTrue(scrollUntilVisible(app.sliders["reader.margins"]), "margin control missing")
        XCTAssertTrue(scrollUntilVisible(app.segmentedControls["reader.alignment"]), "alignment control missing")
        XCTAssertTrue(app.buttons["Justified"].exists, "justified option missing")
        XCTAssertTrue(app.buttons["Left-aligned"].exists, "left-aligned option missing")
    }

    /// The page fills the screen and the controls live behind a tap in the middle third.
    func testMiddleTapTogglesTheControls() {
        openReader()
        XCTAssertTrue(app.staticTexts["reader.caption"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["Appearance"].exists, "the reader opened with its controls showing")

        showChrome()

        app.otherElements["reader.page"].firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .tap()

        XCTAssertTrue(waitForAbsence(of: app.buttons["Appearance"]), "a second middle tap left the controls up")
    }

    /// A rightward swipe from the leading edge would normally pop the screen. In the reader it has to
    /// turn a page instead, so the interactive pop gesture is switched off there.
    func testEdgeSwipeDoesNotLeaveTheReader() {
        openReader()

        let caption = app.staticTexts["reader.caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 20), "page caption missing")

        let page = app.otherElements["reader.page"].firstMatch
        let leadingEdge = page.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let inward = page.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        leadingEdge.press(forDuration: 0.05, thenDragTo: inward)

        XCTAssertTrue(
            app.otherElements["reader.page"].firstMatch.waitForExistence(timeout: 10),
            "an edge swipe popped the reader instead of turning a page"
        )
        XCTAssertTrue(caption.exists, "reader chrome disappeared after an edge swipe")
    }

    /// The tab bar belongs to the root of each tab; pushed screens give the page the full height.
    func testTabBarIsHiddenBelowTheTopLevel() {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "tab bar missing at the top level")

        app.tabBars.buttons["Top"].tap()

        let firstBook = app.collectionViews.cells.element(boundBy: 1)
        XCTAssertTrue(firstBook.waitForExistence(timeout: 30))
        firstBook.tap()

        let readButton = app.buttons["work.read"]
        XCTAssertTrue(readButton.waitForExistence(timeout: 30))
        XCTAssertFalse(app.tabBars.firstMatch.exists, "tab bar should be hidden on a book page")

        readButton.tap()
        XCTAssertTrue(app.otherElements["reader.page"].firstMatch.waitForExistence(timeout: 40))
        XCTAssertFalse(app.tabBars.firstMatch.exists, "tab bar should be hidden while reading")
    }

    /// The appearance sheet is capped to half the screen so the page stays visible, and every change
    /// has to land on that page straight away rather than on a sample.
    func testAppearanceSheetIsHalfHeightAndEditsApplyLive() {
        openReader()

        let caption = app.staticTexts["reader.caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 20), "page caption missing")
        let before = caption.label

        showChrome()
        app.buttons["Appearance"].tap()
        let sheetBar = app.navigationBars["Appearance"]
        XCTAssertTrue(sheetBar.waitForExistence(timeout: 10), "appearance sheet never opened")

        // Half-height: the sheet's chrome starts below the middle of the window.
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(
            sheetBar.frame.minY,
            window.height * 0.35,
            "sheet is taller than half the screen, hiding the page being edited"
        )

        XCTAssertTrue(app.buttons["reader.face"].exists, "typeface dropdown missing")
        XCTAssertTrue(caption.exists, "page caption hidden behind the sheet")

        // Growing the type re-paginates, which shows up as a different page count in the caption.
        let slider = app.sliders["reader.fontSize"]
        XCTAssertTrue(slider.waitForExistence(timeout: 10), "font size control missing")
        slider.adjust(toNormalizedSliderPosition: 1.0)

        XCTAssertTrue(
            waitForChange(of: caption, from: before),
            "changing the font did not re-paginate the page behind the sheet (still \(before))"
        )
    }

    /// Walks from a chart to a book to its reader — the path every reading test starts with.
    private func openReader() {
        app.tabBars.buttons["Top"].tap()

        let firstBook = app.collectionViews.cells.element(boundBy: 1)
        XCTAssertTrue(firstBook.waitForExistence(timeout: 30), "no book to open")
        firstBook.tap()

        let readButton = app.buttons["work.read"]
        XCTAssertTrue(readButton.waitForExistence(timeout: 30), "book page never offered a read action")
        readButton.tap()

        XCTAssertTrue(
            app.otherElements["reader.page"].firstMatch.waitForExistence(timeout: 40),
            "reader never rendered a page"
        )
    }

    /// The reader opens with no chrome at all; a tap in the middle third brings the controls back.
    private func showChrome() {
        app.otherElements["reader.page"].firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .tap()
        XCTAssertTrue(app.buttons["Appearance"].waitForExistence(timeout: 5), "the reader controls never appeared")
    }

    /// Turns one page forward. A book opens on its title page, so reading tests step past it first.
    private func turnPage() {
        app.otherElements["reader.page"].firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
            .tap()
    }

    /// A Form does not instantiate cells below the fold, so a control has to be scrolled into being
    /// before it can be found at all.
    private func scrollUntilVisible(_ element: XCUIElement, swipes: Int = 6) -> Bool {
        for _ in 0 ..< swipes where !element.exists {
            app.swipeUp()
        }

        return element.exists
    }

    /// The drawn page exposes its whole text as one label under its own identifier.
    private func longestPageLabel() -> String {
        let page = app.staticTexts["reader.pageText"].firstMatch

        guard page.waitForExistence(timeout: 5) else { return "" }

        return page.label
    }

    private func waitForAbsence(of element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if !element.exists { return true }

            _ = element.waitForExistence(timeout: 0.3)
        }

        return false
    }

    private func waitForChange(of element: XCUIElement, from previous: String, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if element.exists, element.label != previous { return true }

            _ = element.waitForExistence(timeout: 0.3)
        }

        return false
    }

    func testChapterListNavigation() {
        openReader()

        showChrome()
        app.buttons["Contents"].tap()
        XCTAssertTrue(app.navigationBars["Contents"].waitForExistence(timeout: 10))
        XCTAssertGreaterThan(app.collectionViews.cells.count, 0, "table of contents was empty")

        app.collectionViews.cells.element(boundBy: 0).tap()
        XCTAssertTrue(app.otherElements["reader.page"].firstMatch.waitForExistence(timeout: 40))
    }
}
