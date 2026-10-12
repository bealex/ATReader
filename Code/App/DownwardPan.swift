//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import UIKit

/// A pan that takes a drag straight down and fails on one that leans.
final class DownwardPan: UIPanGestureRecognizer {
    /// How far a finger travels before its direction is read.
    private static let reach: CGFloat = 24

    /// How far across a drag may go for each point down: fifteen degrees off straight down.
    private static let lean: CGFloat = 0.268

    private var start: CGPoint?
    private var isRead = false

    /// True where a finger that has `moved` this far is going down the screen.
    static func isDown(_ moved: CGVector) -> Bool { moved.dy > 0 && abs(moved.dx) <= moved.dy * lean }

    override func reset() {
        super.reset()
        start = nil
        isRead = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)

        if start == nil { start = touches.first?.location(in: nil) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible, !isRead, let start, let now = touches.first?.location(in: nil) {
            let moved = CGVector(dx: now.x - start.x, dy: now.y - start.y)

            // Kept from the pan until then, which would begin on less.
            guard hypot(moved.dx, moved.dy) >= Self.reach else { return }
            guard Self.isDown(moved) else { return state = .failed }

            isRead = true
        }

        super.touchesMoved(touches, with: event)
    }
}
