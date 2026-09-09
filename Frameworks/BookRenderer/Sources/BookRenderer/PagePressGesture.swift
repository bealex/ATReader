//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import UIKit

/// A press that says where it began, keeps saying where the finger is, and takes none of the taps
/// around it.
///
/// UIKit's recognizer rather than SwiftUI's. `LongPressGesture` carries no place of its own, and the
/// drag usually paired with it to find one either waits for the finger to move before it reports
/// anything or swallows every tap on the page: the taps that turn a page, open a note, or show the
/// controls all went that way.
struct PagePressGesture: UIViewRepresentable {
    /// Long enough not to fire on a tap, short enough not to feel like waiting for permission.
    var duration: TimeInterval = 0.22
    var onBegan: (CGPoint) -> Void
    var onMoved: (CGPoint) -> Void
    var onEnded: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = Attaching()
        let recognizer = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.press))

        recognizer.minimumPressDuration = duration
        // Everything else on the page goes on working: this watches the touches rather than taking them.
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = context.coordinator

        view.recognizer = recognizer
        context.coordinator.owner = self
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.owner = self
        (view as? Attaching)?.recognizer?.minimumPressDuration = duration
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var owner: PagePressGesture?
        weak var view: UIView?

        /// True between a press taking hold on the page and the finger coming up.
        private var holding = false

        @objc
        func press(_ recognizer: UILongPressGestureRecognizer) {
            // Counted in the page's own space rather than the window's, so what this reports and what
            // the page's taps arrive in are the same coordinates.
            guard let view, view.window != nil else { return }

            let point = recognizer.location(in: view)

            switch recognizer.state {
                case .began:
                    // The recognizer watches the whole window, since that is the one view certain to
                    // see every touch. A press that began somewhere else is somebody else's.
                    guard view.bounds.contains(point) else { return }

                    holding = true
                    owner?.onBegan(point)
                case .changed:
                    // Not held to the page: a finger drawn off the edge goes on choosing.
                    guard holding else { return }

                    owner?.onMoved(point)
                case .ended, .cancelled, .failed:
                    guard holding else { return }

                    holding = false
                    owner?.onEnded()
                default: break
            }
        }

        func gestureRecognizer(
            _ recognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }

    /// Hangs the recognizer on the window, and never takes a touch itself.
    ///
    /// The window because it is the one view certain to see every touch on the page, whatever SwiftUI
    /// has put in between. Its own hit test answers nothing: a view that answered would be the one the
    /// page's touches landed on, and everything underneath would stop hearing about them.
    final class Attaching: UIView {
        var recognizer: UILongPressGestureRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()

            guard let recognizer else { return }

            recognizer.view?.removeGestureRecognizer(recognizer)

            guard let window else { return }

            window.addGestureRecognizer(recognizer)
        }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }
}
