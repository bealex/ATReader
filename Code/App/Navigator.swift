//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import UIKit

/// Everything the app hands its screens, kept so a screen built outside SwiftUI can be handed it too.
///
/// A hosting controller made inside a representable inherits no environment, and every push builds one,
/// so the list has to be carried rather than read.
@MainActor
struct AppDressing {
    let session: SessionStore
    let settings: ReaderSettings
    let inbox: BookInbox
    let litres: LitresStore
    let backup: LibraryBackup
    let shelf: ShelfSettings
    let origins: BookOrigins

    func dress(_ screen: some View) -> some View {
        screen
            .environment(session)
            .environment(settings)
            .environment(inbox)
            .environment(litres)
            .environment(backup)
            .environment(shelf)
            .environment(origins)
            .environment(\.pagePictures, CoverPictures())
    }
}

/// Where a tab's screens are pushed, so a list can open a book without owning a stack.
///
/// The stack is UIKit's. Only a navigation controller can say that a pushed screen takes the tab bar
/// with it, and the zoom into a book grows out of the very view that was tapped rather than out of a
/// stand-in laid over it.
@Observable @MainActor
final class Navigator {
    /// Moves every time the tab comes back to its own root, for a list that has to read the store again
    /// to see what the reading changed.
    private(set) var returnedAt: Date?

    @ObservationIgnored
    fileprivate weak var controller: UINavigationController?

    @ObservationIgnored
    fileprivate var dressing: AppDressing?

    /// Opens a screen, growing it out of `source` where one is given.
    func push(_ route: AppRoute, from source: UIView? = nil) {
        guard let controller, let dressing else { return }

        let screen = UIHostingController(rootView: dressing.dress(AppRouteDestination(route: route).environment(self)))

        // The bar belongs to the root of a tab; below that the screen has the whole height.
        screen.hidesBottomBarWhenPushed = true

        if let source {
            screen.preferredTransition = .zoom { _ in source }
        }

        controller.pushViewController(screen, animated: true)
    }

    fileprivate func cameBack() { returnedAt = .now }
}

/// Tells the tab's navigator when the stack is back at its root.
@MainActor
final class NavigatorDelegate: NSObject, UINavigationControllerDelegate {
    private let navigator: Navigator

    init(_ navigator: Navigator) {
        self.navigator = navigator
    }

    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        guard viewController === navigationController.viewControllers.first else { return }

        navigator.cameBack()
    }
}

extension Navigator {
    /// Hands this navigator the stack it pushes onto, and what to dress a pushed screen in.
    func drive(_ controller: UINavigationController, dressing: AppDressing) {
        self.controller = controller
        self.dressing = dressing
    }
}
