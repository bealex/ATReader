//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Testing
import UIKit

@testable import Bookhold

/// A table opened whole turns with the device even where the reader locked the page upright.
@MainActor
struct OrientationLockTests {
    @Test
    func releasesALockedScreenUntilHeld() {
        let was = OrientationLock.choice

        defer {
            OrientationLock.hold()
            OrientationLock.apply(was)
        }

        OrientationLock.apply(.portrait)
        #expect(OrientationLock.mask == .portrait)

        OrientationLock.release()
        #expect(OrientationLock.mask.contains(.landscapeLeft))
        #expect(OrientationLock.mask.contains(.landscapeRight))

        OrientationLock.hold()
        #expect(OrientationLock.mask == .portrait)
    }

    /// Held on its side, the page stays that side up, and a wide table has nothing to turn back from.
    @Test
    func holdsTheScreenTurnedWhicheverWayTheReaderChose() {
        let was = OrientationLock.choice

        defer { OrientationLock.apply(was) }

        OrientationLock.apply(.turnedLeft)
        #expect(OrientationLock.mask == .landscapeRight)
        #expect(!OrientationLock.holdsUpright)

        OrientationLock.apply(.turnedRight)
        #expect(OrientationLock.mask == .landscapeLeft)
    }

    /// Unlocked, holding changes nothing: the screen already turns.
    @Test
    func leavesAnUnlockedScreenAlone() {
        let was = OrientationLock.choice

        defer { OrientationLock.apply(was) }

        OrientationLock.apply(.free)
        OrientationLock.release()
        OrientationLock.hold()
        #expect(OrientationLock.mask.contains(.landscapeLeft))
    }
}
