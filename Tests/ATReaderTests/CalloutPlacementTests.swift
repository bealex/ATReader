//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import DesignSystem
import Foundation
import Testing

/// Where an aside stands once it has been hung over something.
///
/// This was a popover's job and is now the app's own arithmetic, which is why it is checked here
/// rather than through a screen. Two things went wrong before: an aside that ignored what it belonged
/// to and hung from the corner of whatever it was attached to, and one that opened straight over the
/// words it had been asked about.
struct CalloutPlacementTests {
    private static let room = CGSize(width: 400, height: 800)
    private static let width: CGFloat = 300
    private static let margin: CGFloat = 12

    private static func placed(_ rect: CGRect) -> CalloutPlacement {
        CalloutPlacement.make(over: rect, in: room, width: width, margin: margin)
    }

    private static func word(atX x: CGFloat, y: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: 60, height: 20)
    }

    @Test
    func anAsideStandsOverWhatItBelongsTo() {
        #expect(Self.placed(Self.word(atX: 170, y: 400)).across == 200)
        #expect(Self.placed(Self.word(atX: 150, y: 400)).across == 180)
    }

    /// The whole of the aside has to stay on screen, however near an edge the thing was.
    @Test
    func anAsideSlidesInFromTheEdges() {
        #expect(Self.placed(Self.word(atX: -30, y: 400)).across == Self.width / 2 + Self.margin)
        #expect(Self.placed(Self.word(atX: 380, y: 400)).across == Self.room.width - Self.width / 2 - Self.margin)
    }

    /// A card sits above what it points at where there is more room above, and below where there isn't.
    @Test
    func anAsideTakesTheSideWithTheRoom() {
        #expect(Self.placed(Self.word(atX: 170, y: 700)).pointsDown)
        #expect(!Self.placed(Self.word(atX: 170, y: 100)).pointsDown)
    }

    /// The point of the whole rule: an aside never stands over the words it was opened for.
    @Test
    func anAsidePointsAtTheNearEdgeRatherThanTheMiddle() {
        let high = Self.word(atX: 170, y: 100)
        let low = Self.word(atX: 170, y: 700)

        // Below the words: it points at their underside, and everything above that stays in sight.
        #expect(Self.placed(high).along == high.maxY)
        // Above the words: it points at their top.
        #expect(Self.placed(low).along == low.minY)
    }

    /// A card with nowhere to slide is centred rather than pushed off one side.
    @Test
    func anAsideWiderThanItsRoomIsCentred() {
        let narrow = CGSize(width: 280, height: 800)
        let placement = CalloutPlacement.make(over: Self.word(atX: 0, y: 400), in: narrow, width: 300, margin: 12)

        #expect(placement.across == 140)
    }
}
