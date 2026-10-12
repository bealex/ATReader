//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import CoreGraphics
import Testing

@testable import Bookhold

/// Which drags shut a book: the ones going straight down, give or take fifteen degrees.
struct DownwardPanTests {
    @Test(arguments: [ 0.0, 5, 10, 14, -14 ])
    func aDragNearStraightDownIsOne(degrees: Double) {
        #expect(DownwardPan.isDown(Self.drag(leaning: degrees)))
    }

    @Test(arguments: [ 16.0, -16, 30, 45, 80, 90, 135, 180 ])
    func aDragThatLeansIsNot(degrees: Double) {
        #expect(!DownwardPan.isDown(Self.drag(leaning: degrees)))
    }

    /// A drag of some length `degrees` off straight down, towards the trailing side when positive.
    private static func drag(leaning degrees: Double) -> CGVector {
        let angle = degrees * .pi / 180

        return CGVector(dx: 40 * sin(angle), dy: 40 * cos(angle))
    }
}
