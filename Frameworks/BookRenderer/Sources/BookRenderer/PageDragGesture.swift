//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import UIKit

/// A drag across the page, as the page turner reads it.
public struct PageDrag {
    public var translation: CGSize
    public var location: CGPoint
    /// Where the finger would come to rest if it were let go now.
    public var predictedEndTranslation: CGSize
    public var time: Date

    /// How far a flick is taken to carry past where it was let go, as a share of a second's travel.
    /// The turn's own thresholds are counted in that distance, so this is what they mean.
    static let projection: CGFloat = 0.1
}

/// The drag that turns a page, and only that drag.
///
/// UIKit's recognizer rather than SwiftUI's, for the reason the press beside it is one.
/// `DragGesture` recognises in every direction and takes the touch at eight points, so a drag down
/// the page was the page's before anything else could ask for it, and the zoom transition's own way
/// out of the book could never begin. This one fails on a drag up or down, which hands that drag on.
struct PageDragGesture: UIViewRepresentable {
    var onChanged: (PageDrag) -> Void
    var onEnded: (PageDrag) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = Attaching()
        let recognizer = HorizontalPan(target: context.coordinator, action: #selector(Coordinator.drag))

        // Everything else on the page goes on working: this watches the touches rather than taking them.
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        recognizer.page = view

        view.recognizer = recognizer
        context.coordinator.owner = self
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.owner = self
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var owner: PageDragGesture?
        weak var view: UIView?

        @objc
        func drag(_ recognizer: HorizontalPan) {
            guard let view, view.window != nil else { return }

            let translation = recognizer.translation(in: view)
            let velocity = recognizer.velocity(in: view)
            let drag = PageDrag(
                translation: CGSize(width: translation.x, height: translation.y),
                location: recognizer.location(in: view),
                predictedEndTranslation: CGSize(
                    width: translation.x + velocity.x * PageDrag.projection,
                    height: translation.y + velocity.y * PageDrag.projection
                ),
                time: .now
            )

            switch recognizer.state {
                case .began, .changed: owner?.onChanged(drag)
                case .ended, .cancelled, .failed: owner?.onEnded(drag)
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
    /// has put in between. Its own hit test answers nothing, so everything underneath goes on hearing
    /// about them.
    final class Attaching: UIView {
        var recognizer: HorizontalPan?

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

/// A pan that takes a drag across the page and fails on one up or down it.
final class HorizontalPan: UIPanGestureRecognizer {
    /// The page, which decides whether a touch is this one's and is the space it reports in.
    weak var page: UIView?

    /// How far a finger travels before its direction is read. Under the pan's own threshold, so the
    /// answer is in before the drag would have begun.
    private static let slop: CGFloat = 6

    private var start: CGPoint?

    override func reset() {
        super.reset()
        start = nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)

        guard
            let page, let touch = touches.first, page.window != nil,
            // The recognizer hangs on the window, so it hears every touch on the screen. One that began
            // off the page belongs to somebody else.
            page.bounds.contains(touch.location(in: page)),
            !isUnderASheet(page)
        else { return state = .failed }

        start = touch.location(in: page)
    }

    /// True where something is presented over the page.
    ///
    /// A sheet covers the page without moving it, and the page's bounds still hold every point of the
    /// screen, so a drag inside the settings would turn the page behind it. Asked of the controllers
    /// rather than of the views: the page's own text is drawn rather than laid out in views, so a hit
    /// test lands in a subtree beside this one and says nothing about what covers what.
    ///
    /// Only this screen's own controllers are asked, by walking parents. The responder chain runs past
    /// them and out through whatever presented this screen, and a reader presented over the library
    /// found the library presenting *it* and took every drag for a covered one.
    private func isUnderASheet(_ page: UIView) -> Bool {
        var responder: UIResponder? = page.next
        var controller: UIViewController?

        while let next = responder, controller == nil {
            controller = next as? UIViewController
            responder = next.next
        }

        while let current = controller {
            if current.presentedViewController != nil { return true }

            controller = current.parent
        }

        return false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        // Read before the pan is given the touches: a flick arrives as one move long enough to begin
        // it, and a pan that has begun cannot fail.
        if state == .possible, let page, let start,
                let now = touches.first?.location(in: page) {
            let across = abs(now.x - start.x)
            let along = abs(now.y - start.y)

            if max(across, along) > Self.slop, along > across { return state = .failed }
        }

        super.touchesMoved(touches, with: event)
    }
}
