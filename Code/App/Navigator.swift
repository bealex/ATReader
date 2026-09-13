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
    /// Moves every time the tab comes back to its own root, or a screen presented over it goes, for a
    /// list that has to read the store again to see what the reading changed.
    private(set) var returnedAt: Date?

    /// Told as a presented screen starts to go, before the transition has taken its picture of what it
    /// is going home to. Whoever is on that screen writes what it holds here, so the shelf underneath
    /// has it in time to be seen.
    @ObservationIgnored
    var aboutToGo: (@MainActor () -> Void)?

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
            screen.preferredTransition = .zoom(options: Self.zoom) { _ in source }
        }

        controller.pushViewController(screen, animated: true)
    }

    /// Opens a screen over everything, growing it out of `source` where one is given.
    ///
    /// Presented rather than pushed, for a screen that wants the whole window. A pushed one has to
    /// take the tab bar away on the way in and give it back on the way out, and the stack's own bar
    /// with it, and the reader was left re-laying all of that out in the middle of the zoom: that is
    /// the jump the transition had. A presented screen covers them instead, so nothing underneath
    /// moves at all.
    func present(_ route: AppRoute, from source: (@MainActor @Sendable (BookZoom) -> UIView?)? = nil) {
        guard let controller, let dressing else { return }

        let screen = PresentedScreen(rootView: dressing.dress(AppRouteDestination(route: route).environment(self)))

        // Over, not simply full screen. A full-screen presentation takes the presenting view out of
        // the window, so a shelf spends the whole reading session off it: its cells are built again
        // and its spines printed again only once the reader has gone, which lands as one frame of
        // everything moving at the end of the zoom. Left in the window, the shelf keeps up while it
        // is covered and is already right when it is uncovered.
        screen.modalPresentationStyle = .overFullScreen

        // An over-full-screen presentation leaves the status bar with whoever is underneath, so the
        // reader's own `.statusBarHidden` would go unread and the bar stay up over a hidden toolbar.
        screen.modalPresentationCapturesStatusBarAppearance = true

        // Asked afresh each time, on the way in and on the way out. A shelf lays itself out again
        // around whatever the reading changed, so the board a book stood on when it opened is the
        // wrong size by the time the book closes, and the zoom landed on one and left the other.
        if let source {
            screen.preferredTransition = .zoom(options: Self.zoom) { _ in source(.running) }
            // The book is taken down once the reader is over it, so it is never standing there behind
            // its own transition, and put back when the zoom has finished bringing it home.
            screen.onArrived = { source(.covered) }
        }

        // The going is reported twice, and the two are different moments. This one is the transition
        // starting, which is the last chance to put right what the zoom is about to take a picture of.
        screen.onGoing = { [weak self] in self?.aboutToGo?() }

        // A screen that covers the stack never pops it, so the delegate that reports a return never
        // hears of this one and a list would go on showing what it read before the reading.
        screen.onGone = { [weak self] in
            source?(.done)
            self?.cameBack()
        }

        controller.present(screen, animated: true)
    }

    /// A presented screen that says when it has arrived and when it has gone.
    ///
    /// A dismissal begun by dragging is nobody's to call, so there is no completion to hang this on:
    /// the screen's own life is what reports it. A drag let go half way brings `viewDidAppear` round
    /// again, which is the answer wanted there too.
    private final class PresentedScreen<Content: View>: UIHostingController<Content> {
        var onArrived: (@MainActor () -> Void)?
        /// The transition beginning, a drag's included: a drag let go half way is answered by
        /// `viewDidAppear` coming round again.
        var onGoing: (@MainActor () -> Void)?
        var onGone: (@MainActor () -> Void)?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onArrived?()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            onGoing?()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            onGone?()
        }
    }

    /// A zoomed screen is closed by dragging it back down, and only down.
    ///
    /// The dismissal answers a drag in any direction by default, and the reader turns its pages with
    /// the sideways ones: a drag in from the leading edge closed the book instead of turning back a
    /// page. Everything the screen has no use for is still the transition's.
    private static let zoom: UIViewController.Transition.ZoomOptions = {
        let options = UIViewController.Transition.ZoomOptions()

        options.interactiveDismissShouldBegin = { interaction in
            interaction.willBegin && interaction.velocity.dy > abs(interaction.velocity.dx)
        }

        return options
    }()

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
