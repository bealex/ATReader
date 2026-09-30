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
        let wasPortraitOnly = OrientationLock.isPortraitOnly

        defer {
            OrientationLock.hold()
            OrientationLock.apply(portraitOnly: wasPortraitOnly)
        }

        OrientationLock.apply(portraitOnly: true)
        #expect(OrientationLock.mask == .portrait)

        OrientationLock.release()
        #expect(OrientationLock.mask.contains(.landscapeLeft))
        #expect(OrientationLock.mask.contains(.landscapeRight))

        OrientationLock.hold()
        #expect(OrientationLock.mask == .portrait)
    }

    /// Unlocked, holding changes nothing: the screen already turns.
    @Test
    func leavesAnUnlockedScreenAlone() {
        let wasPortraitOnly = OrientationLock.isPortraitOnly

        defer { OrientationLock.apply(portraitOnly: wasPortraitOnly) }

        OrientationLock.apply(portraitOnly: false)
        OrientationLock.release()
        OrientationLock.hold()
        #expect(OrientationLock.mask.contains(.landscapeLeft))
    }
}
