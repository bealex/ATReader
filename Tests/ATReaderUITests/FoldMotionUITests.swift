//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import UIKit
import XCTest

/// A book shows one of its two panels, and the other only while it is turning between them.
///
/// The trap is a panel standing exactly flat to the eye: it projects onto a line, and a transform that
/// flattens what it is given is dropped rather than applied, which draws the cover full size beside the
/// spine instead of not at all. Nothing but the painted screen catches that, so it is measured here.
final class FoldMotionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [ "-at-design-system", "YES" ]
        app.launch()
    }

    func testAShelvedBookShowsNothingOfItsCoverAndOneTakenDownNothingOfItsSpine() throws {
        app.segmentedControls["catalog.segment"].buttons["Motion"].tap()

        let row = app.descendants(matching: .any).matching(identifier: "catalog.fold.book").element(boundBy: 0)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the catalogue has no fold in it")

        let turn = app.buttons.matching(identifier: "catalog.fold.turn").element(boundBy: 0)
        let field = CGRect(x: row.frame.minX, y: row.frame.minY, width: Self.field, height: row.frame.height)

        let shelved = try painted(inside: field)
        XCTAssertLessThan(shelved, Self.spine, "a book on its edge painted more than a spine's worth")

        turn.tap()
        Thread.sleep(forTimeInterval: 3)

        let taken = try painted(inside: field)
        XCTAssertGreaterThan(taken, Self.cover, "a book taken down painted less than a cover's worth")

        turn.tap()
        Thread.sleep(forTimeInterval: 3)

        XCTAssertLessThan(try painted(inside: field), Self.spine, "the book never went back on its edge")
    }

    /// How wide the fold is drawn, measured off the screen rather than taken from its frame: what went
    /// wrong was drawn outside the frame it was laid out in.
    private func painted(inside field: CGRect) throws -> CGFloat {
        let shot = XCUIScreen.main.screenshot()
        let image = try XCTUnwrap(shot.image.cgImage, "no screenshot came back")
        let reader = try XCTUnwrap(PixelReader(image: image))
        let scale = CGFloat(image.width) / app.frame.width
        let scaled = CGRect(
            x: field.minX * scale,
            y: field.minY * scale,
            width: field.width * scale,
            height: field.height * scale
        )

        // The card the specimen stands on, read where nothing is drawn over it.
        let card = try XCTUnwrap(reader.colour(atX: scaled.maxX - 2, y: scaled.midY), "the card has no colour")
        let box = try XCTUnwrap(reader.bounds(differingFrom: card, tolerance: 12, inside: scaled), "nothing drawn")

        return box.width / scale
    }

    /// How far to the right of the fold to look, which is well past the width of a cover.
    private static let field: CGFloat = 300

    /// What a spine may cover, and what a cover has to.
    private static let spine: CGFloat = 60
    private static let cover: CGFloat = 100
}
