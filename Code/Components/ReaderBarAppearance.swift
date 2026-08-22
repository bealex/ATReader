//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import UIKit

extension View {
    /// Paints the navigation bar in the page's own colour and drops a shadow under it while this view
    /// is on screen.
    ///
    /// SwiftUI's `toolbarBackground` takes a colour but offers no way to ask for a shadow, and a bar
    /// the same colour as the page has no edge without one. `isVisible` is what re-applies the
    /// appearance: SwiftUI configures the bar itself each time it comes back.
    func readerBarAppearance(background: Color, isVisible: Bool) -> some View {
        self.background(
            ReaderBarAppearance(background: UIColor(background), isVisible: isVisible)
                .frame(width: 0, height: 0)
        )
    }
}

/// An empty controller whose only job is to reach the enclosing navigation bar.
private struct ReaderBarAppearance: UIViewControllerRepresentable {
    let background: UIColor
    let isVisible: Bool

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.apply(background: background)
    }

    final class Controller: UIViewController {
        /// What the bar looked like before the reader took it over.
        private struct Saved {
            let standard: UINavigationBarAppearance
            let scrollEdge: UINavigationBarAppearance?
            let compact: UINavigationBarAppearance?
        }

        private var background: UIColor?
        private var saved: Saved?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply(background: background)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            restore()
        }

        func apply(background: UIColor?) {
            self.background = background

            guard let background, let navigationBar = navigationController?.navigationBar else { return }

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

        /// Every other screen expects the bar the navigation stack gave it.
        private func restore() {
            guard let navigationBar = navigationController?.navigationBar, let saved else { return }

            navigationBar.standardAppearance = saved.standard
            navigationBar.scrollEdgeAppearance = saved.scrollEdge
            navigationBar.compactAppearance = saved.compact
            navigationBar.layer.shadowOpacity = 0
        }
    }
}
