//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

#if canImport(UIKit)

    import SwiftUI
    import UIKit

    /// What a navigation stack's own back gesture is left to do on a screen that answers drags itself.
    public enum BackSwipe {
        /// A drag down the screen closes it; every sideways one belongs to the screen.
        case downward
        /// None of them, for as long as the screen has the touch for something of its own.
        case none
    }

    public extension View {
        /// Holds the stack's back gesture to the drags this screen has no use for.
        ///
        /// A screen pushed with a zoom transition is closed by dragging it, and that is the same drag
        /// the reader turns pages with. A pan of this view's own stands in front of the stack's: a
        /// sideways drag begins that pan and the stack's gesture is held off, a drag up or down the
        /// screen fails it and the stack takes the drag.
        func backSwipe(_ allowed: BackSwipe) -> some View {
            background(BackSwipeGuard(allowed: allowed).frame(width: 0, height: 0))
        }
    }

    /// An empty controller whose only job is to hang that pan where the stack's gesture will see it.
    private struct BackSwipeGuard: UIViewControllerRepresentable {
        let allowed: BackSwipe

        func makeUIViewController(context: Context) -> Controller {
            Controller()
        }

        func updateUIViewController(_ controller: Controller, context: Context) {
            controller.allowed = allowed
        }

        final class Controller: UIViewController, UIGestureRecognizerDelegate {
            var allowed: BackSwipe = .downward {
                didSet { pan.takesEverything = allowed == .none }
            }

            private lazy var pan: DirectionalPan = {
                let pan = DirectionalPan(target: self, action: #selector(stand))

                // It stands in front of the stack's gesture and does nothing else: every touch goes on
                // to whatever the screen makes of it.
                pan.cancelsTouchesInView = false
                pan.delaysTouchesBegan = false
                pan.delaysTouchesEnded = false
                pan.maximumNumberOfTouches = 1
                pan.delegate = self
                return pan
            }()

            override func viewDidAppear(_ animated: Bool) {
                super.viewDidAppear(animated)

                // The window, since that is the one view certain to see every touch on the screen,
                // whatever SwiftUI has put in between.
                pan.view?.removeGestureRecognizer(pan)
                view.window?.addGestureRecognizer(pan)
                pan.takesEverything = allowed == .none
            }

            override func viewWillDisappear(_ animated: Bool) {
                super.viewWillDisappear(animated)
                // Handed back whole: every other screen expects the gesture in every direction.
                pan.view?.removeGestureRecognizer(pan)
            }

            @objc
            private func stand() {}

            /// Asked rather than set with `require(toFail:)`, which cannot be taken back off a
            /// recognizer the whole stack shares.
            func gestureRecognizer(
                _ recognizer: UIGestureRecognizer,
                shouldBeRequiredToFailBy other: UIGestureRecognizer
            ) -> Bool {
                other === navigationController?.interactivePopGestureRecognizer
            }

            func gestureRecognizer(
                _ recognizer: UIGestureRecognizer,
                shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
            ) -> Bool {
                true
            }
        }
    }

    /// A pan that takes sideways drags only, so whatever waits on it to fail is left the rest.
    private final class DirectionalPan: UIPanGestureRecognizer {
        /// True where the screen has the touch for something of its own and no drag is to go past.
        var takesEverything = false

        /// How far a finger travels before its direction is read. Under a pan's own threshold, so the
        /// answer is in before this one would have begun.
        private static let slop: CGFloat = 6

        private var start: CGPoint?

        override func reset() {
            super.reset()
            start = nil
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesBegan(touches, with: event)
            start = touches.first?.location(in: view)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            // Read before the pan is given the touches: a flick arrives as one move long enough to
            // begin it, and a pan that has begun cannot fail.
            if state == .possible, !takesEverything, let start,
                    let now = touches.first?.location(in: view) {
                let sideways = abs(now.x - start.x)
                let along = abs(now.y - start.y)

                if max(sideways, along) > Self.slop, along > sideways {
                    state = .failed
                    return
                }
            }

            super.touchesMoved(touches, with: event)
        }
    }
#endif
