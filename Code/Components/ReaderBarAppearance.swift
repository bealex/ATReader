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

        /// Held from the moment the bar is taken over, because a controller on its way out of the stack
        /// has already lost sight of its navigation controller and would restore nothing.
        private weak var takenBar: UINavigationBar?
        private weak var takenWindow: UIWindow?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply(background: background, style: style)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            restore()
        }

        func apply(background: UIColor?, style: UIUserInterfaceStyle) {
            self.background = background
            self.style = style

            if let window = view.window {
                takenWindow = window
                window.overrideUserInterfaceStyle = style
            }

            guard let background, let navigationBar = navigationController?.navigationBar else { return }

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
            takenWindow?.overrideUserInterfaceStyle = .unspecified
            takenWindow = nil

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
    }
}
