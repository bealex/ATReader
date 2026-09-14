//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Testing
import UIKit

@testable import Bookhold

/// A book opened from its own page grows out of the cover at the top of it.
///
/// The rule is the shelf's: while the zoom runs the anchor stands in for the cover, so the screen
/// growing out of it and the cover it grew out of are never both drawn. Two of one cover, one growing
/// and one holding still, is what gives the zoom away.
@MainActor
struct CoverZoomTests {
    @Test
    func showsNothingOfItsOwnUntilNoZoomIsRunning() {
        let anchor = CoverAnchor()

        #expect(!anchor.isZooming, "a cover nothing is zooming into draws itself")

        _ = anchor.face(during: .running)

        #expect(anchor.isZooming)

        _ = anchor.face(during: .covered)

        #expect(anchor.isZooming)

        _ = anchor.face(during: .done)

        #expect(!anchor.isZooming, "the cover never came back")
    }

    /// The anchor carries the whole cover, and goes itself once the reader covers the screen.
    @Test
    func standsInForTheCoverWhileTheZoomRuns() {
        let anchor = CoverAnchor()
        let view = UIImageView()

        anchor.stands(on: view)
        anchor.picture = UIImage()

        #expect(anchor.face(during: .running) === view)
        #expect(view.image === anchor.picture, "the zoom grew out of a bare view")
        #expect(!view.isHidden)

        _ = anchor.face(during: .covered)

        #expect(view.isHidden, "the anchor stayed on a screen the reader had covered")

        _ = anchor.face(during: .done)

        #expect(!view.isHidden)
    }
}
