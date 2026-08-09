//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import UIKit

extension View {
    /// Turns off the navigation stack's swipe-from-the-edge-to-go-back gesture while this view is on
    /// screen.
    ///
    /// The reader turns pages with horizontal swipes, and the system's interactive pop gesture competes
    /// with them: a rightward swipe that starts near the leading edge pops the screen instead of turning
    /// back a page. SwiftUI exposes no way to disable it without also hiding the back button, so this
    /// reaches the underlying `UINavigationController` directly.
    func backSwipeDisabled(_ isDisabled: Bool = true) -> some View {
        background(BackSwipeDisabler(isDisabled: isDisabled).frame(width: 0, height: 0))
    }
}

/// An empty controller whose only job is to find the enclosing navigation controller.
private struct BackSwipeDisabler: UIViewControllerRepresentable {
    let isDisabled: Bool

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.isDisabled = isDisabled
    }

    final class Controller: UIViewController {
        var isDisabled = true {
            didSet { apply(isDisabled) }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply(isDisabled)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            // Always hand the gesture back: every other screen expects it to work.
            apply(false)
        }

        /// `navigationController` walks the parent chain, so it resolves through the SwiftUI hosting
        /// controller this view is embedded in.
        private func apply(_ disabled: Bool) {
            navigationController?.interactivePopGestureRecognizer?.isEnabled = !disabled
        }
    }
}
