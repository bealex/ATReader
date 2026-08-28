//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import UIKit

extension View {
    /// Paints the navigation bar in the page's own colour, drops a shadow under it, and holds the whole
    /// window to the page's light or dark, all for as long as this view is on screen.
    ///
    /// SwiftUI's `toolbarBackground` takes a colour but offers no way to ask for a shadow, and a bar the
    /// same colour as the page has no edge without one. `isVisible` is what re-applies the appearance,
    /// since SwiftUI configures the bar itself each time it comes back.
    ///
    /// The system flipping between light and dark re-applies it too, and has to be watched for rather
    /// than waited on: on the theme that follows the system, neither the page's colour nor the reader's
    /// settings change value when it flips, so nothing here would otherwise re-run.
    ///
    /// The light or dark belongs here rather than in `preferredColorScheme` because that modifier is
    /// applied by overriding the window, and leaving the reader reverts SwiftUI's own side of it without
    /// clearing the window's. The list underneath came back light while the bar and its search field
    /// stayed dark. An override with one owner and a definite end doesn't strand anything.
    func readerBarAppearance(background: Color, colorScheme: ColorScheme?, isVisible: Bool) -> some View {
        self.background(
            ReaderBarAppearance(
                background: UIColor(background),
                style: UIUserInterfaceStyle(colorScheme),
                isVisible: isVisible
            )
            .frame(width: 0, height: 0)
        )
    }
}

extension UIUserInterfaceStyle {
    init(_ colorScheme: ColorScheme?) {
        switch colorScheme {
            case .light: self = .light
            case .dark: self = .dark
            default: self = .unspecified
        }
    }
}

/// An empty controller whose only job is to reach the enclosing navigation bar and window.
private struct ReaderBarAppearance: UIViewControllerRepresentable {
    let background: UIColor
    let style: UIUserInterfaceStyle
    let isVisible: Bool

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.apply(background: background, style: style)
    }

    final class Controller: UIViewController {
        /// What the bar looked like before the reader took it over.
        private struct Saved {
            let standard: UINavigationBarAppearance
            let scrollEdge: UINavigationBarAppearance?
            let compact: UINavigationBarAppearance?
        }

        private var background: UIColor?
        private var style: UIUserInterfaceStyle = .unspecified
        private var saved: Saved?

        /// True between appearing and disappearing.
        ///
        /// SwiftUI goes on updating a representable through a dismissal, so an update can land after the
        /// bar and the window have been given back. Taking them again then leaves the window pinned to
        /// the reader's light or dark with nothing on its way to clear it, and a pinned window never
        /// changes traits, so every bar in the app stops following the system.
        private var isOnScreen = false

        /// Held from the moment the bar is taken over, because a controller on its way out of the stack
        /// has already lost sight of its navigation controller and would restore nothing.
        private weak var takenBar: UINavigationBar?
        private weak var takenWindow: UIWindow?

        override func viewDidLoad() {
            super.viewDidLoad()

            // The page's colour is the system's own on the theme that follows it, and neither it nor
            // the reader's settings change value when the system flips. So nothing upstream re-runs,
            // and the bar would keep the colour it was built with until something else disturbed it.
            registerForTraitChanges([ UITraitUserInterfaceStyle.self ]) { (controller: Controller, _) in
                guard controller.isOnScreen else { return }

                controller.apply(background: controller.background, style: controller.style)
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            isOnScreen = true
            apply(background: background, style: style)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            isOnScreen = false
            restore()
        }

        /// Given up again on the way out, in case an update landed while the dismissal was running.
        /// Restoring twice costs nothing: the second run has nothing left to put back.
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            isOnScreen = false
            restore()
        }

        func apply(background: UIColor?, style: UIUserInterfaceStyle) {
            self.background = background
            self.style = style

            if isOnScreen, let window = view.window {
                takenWindow = window
                window.overrideUserInterfaceStyle = style
            }

            // On screen, for the bar as much as for the window. An update landing during a pop would
            // otherwise take the bar back after it had been given up, with nothing left on the way out
            // to return it, and the screen underneath kept the reader's colour.
            guard isOnScreen, let background, let navigationBar = navigationController?.navigationBar else { return }

            takenBar = navigationBar

            if saved == nil {
                saved = Saved(
                    standard: navigationBar.standardAppearance,
                    scrollEdge: navigationBar.scrollEdgeAppearance,
                    compact: navigationBar.compactAppearance
                )
            }

            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = background
            // The bar's own hairline would be a line drawn on the page; the shadow below is the edge.
            appearance.shadowColor = nil
            navigationBar.standardAppearance = appearance
            navigationBar.scrollEdgeAppearance = appearance
            navigationBar.compactAppearance = appearance

            navigationBar.layer.masksToBounds = false
            navigationBar.layer.shadowColor = UIColor.black.cgColor
            navigationBar.layer.shadowOpacity = 0.18
            navigationBar.layer.shadowRadius = 5
            navigationBar.layer.shadowOffset = CGSize(width: 0, height: 2)
        }

        /// Every other screen expects the bar the navigation stack gave it, and the window's own light
        /// or dark back.
        private func restore() {
            releaseWindow()

            guard let navigationBar = takenBar ?? navigationController?.navigationBar, let saved else { return }

            navigationBar.standardAppearance = saved.standard
            navigationBar.scrollEdgeAppearance = saved.scrollEdge
            navigationBar.compactAppearance = saved.compact
            navigationBar.layer.shadowOpacity = 0

            // Taken again on the way back in, so the bar is read as the rest of the app last left it
            // rather than as it stood the first time the reader opened.
            self.saved = nil
            takenBar = nil
        }

        private func releaseWindow() {
            takenWindow?.overrideUserInterfaceStyle = .unspecified
            takenWindow = nil
        }
    }
}
