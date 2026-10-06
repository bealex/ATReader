//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import UIKit.UIGestureRecognizerSubclass

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
            screen.preferredTransition = .zoom(options: Self.zoom(for: screen)) { _ in source }
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

        let screen = presented(route, dressed: dressing)

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
            // A cover in full view opens onto the page; anything else, a spine among them, zooms.
            if let opening = BookOpening(
                from: source,
                paper: { [settings = dressing.settings] in UIColor(settings.theme.background) },
                read: route.readingProgress ?? 0
            ) {
                screen.opening = opening
                screen.transitioningDelegate = opening
                opening.shuts(screen)
            } else {
                // Asked for on the way in and again on the way out, a drag to dismiss included, and
                // answered the same way both times: the stand-in, standing exactly where the cover stands.
                screen.preferredTransition = .zoom(options: Self.zoom(for: screen)) { _ in source(.running) }
            }
            // The book is taken down once the reader is over it, so it is never standing there behind
            // its own transition, and put back when the zoom has finished bringing it home.
            screen.onArrived = { _ = source(.covered) }
        }

        // The going is reported twice, and the two are different moments. This one is the transition
        // starting, which is the last chance to put right what the zoom is about to take a picture of.
        screen.onGoing = { [weak self] in self?.aboutToGo?() }

        // A screen that covers the stack never pops it, so the delegate that reports a return never
        // hears of this one and a list would go on showing what it read before the reading.
        screen.onGone = { [weak self] in
            _ = source?(.done)
            self?.cameBack()
        }

        controller.present(screen, animated: true)
    }

    /// The screen a route opens over everything. The reader is built by hand, so that opening a book
    /// sets out the page alone; every other screen is SwiftUI's.
    private func presented(_ route: AppRoute, dressed dressing: AppDressing) -> any PresentedScreenReporting {
        if case let .reader(reader) = route {
            return ReaderScreen.Controller(
                workId: reader.workId,
                title: reader.title,
                initialChapterId: reader.chapterId,
                session: dressing.session,
                settings: dressing.settings,
                navigator: self,
                pictures: CoverPictures()
            )
        }

        return PresentedScreen(rootView: dressing.dress(AppRouteDestination(route: route).environment(self)))
    }

    /// A presented screen that says when it has arrived and when it has gone.
    ///
    /// A dismissal begun by dragging is nobody's to call, so there is no completion to hang this on:
    /// the screen's own life is what reports it. A drag let go half way brings `viewDidAppear` round
    /// again, which is the answer wanted there too.
    private final class PresentedScreen<Content: View>: UIHostingController<Content>, PresentedScreenReporting {
        var opening: BookOpening?
        var onArrived: (@MainActor () -> Void)?
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

    /// A zoomed screen is closed by dragging it back down, and only down, from below the top edge.
    ///
    /// The dismissal answers a drag in any direction by default, and the reader turns its pages with
    /// the sideways ones: a drag in from the leading edge closed the book instead of turning back a
    /// page. A drag from the top edge is the system's, for Control Center or notifications: it takes
    /// the touch half way, and a dismissal whose touch is cancelled finishes rather than going back.
    private static func zoom(for screen: UIViewController) -> UIViewController.Transition.ZoomOptions {
        let touchDown = TouchDownRecognizer()
        let options = UIViewController.Transition.ZoomOptions()

        screen.view.addGestureRecognizer(touchDown)
        options.interactiveDismissShouldBegin = { [weak touchDown] interaction in
            guard interaction.willBegin, interaction.velocity.dy > abs(interaction.velocity.dx) else { return false }

            return touchDown?.beganAtTopEdge != true
        }

        return options
    }

    fileprivate func cameBack() {
        returnedAt = .now
        // Another window showing the shelf has no other way to learn a book was read in this one.
        BookInbox.shared.libraryChanged(by: self)
    }
}

/// A screen presented over everything, which holds its own opening and reports its own coming and going.
@MainActor
protocol PresentedScreenReporting: UIViewController {
    /// Held here since a transitioning delegate is held weakly.
    var opening: BookOpening? { get set }
    var onArrived: (@MainActor () -> Void)? { get set }
    /// The transition beginning, a drag's included: a drag let go half way is answered by
    /// `viewDidAppear` coming round again.
    var onGoing: (@MainActor () -> Void)? { get set }
    var onGone: (@MainActor () -> Void)? { get set }
}

/// Notes whether the latest touch came down in the band at the top of the window where the system's
/// own swipes begin, and never recognises anything itself.
private final class TouchDownRecognizer: UIGestureRecognizer {
    private(set) var beganAtTopEdge = false

    override init(target: Any? = nil, action: Selector? = nil) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, let window = touch.window {
            beganAtTopEdge = touch.location(in: window).y < window.safeAreaInsets.top
        }

        state = .failed
    }
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
