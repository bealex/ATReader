//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import XCTest

extension XCTestCase {
    /// Opens the invented library, which needs no account, and waits for it to be drawn.
    func launchDemoLibrary() throws -> XCUIApplication {
        let app = XCUIApplication()

        app.launchArguments = [ "-at-ui-test-guest", "-at-demo-library", "YES" ]
        app.launch()

        XCTAssertTrue(app.collectionViews["library.list"].waitForExistence(timeout: 30), "the library never showed")

        // Covers are painted in the background; a shelf photographed before they land is a blank one.
        Thread.sleep(forTimeInterval: 3)

        return app
    }

    /// Files a screenshot under `Fixtures/Reports`, for a person to look at afterwards.
    func report(_ shot: XCUIScreenshot, named name: String) throws {
        let reports = ProcessInfo.processInfo.environment["AT_REPORTS"] ?? NSTemporaryDirectory()
        let folder = URL(fileURLWithPath: reports).appendingPathComponent("shelf")

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try shot.pngRepresentation.write(to: folder.appendingPathComponent(name))
    }
}
