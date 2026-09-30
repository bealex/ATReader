//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import DesignSystem
import UIKit

/// How a screen presented from a book's cover comes and goes: the cover opens onto the page, and shuts
/// over it again. A drag down the screen shuts it by hand.
@MainActor
final class BookOpening: NSObject {
    private let source: @MainActor @Sendable (BookZoom) -> UIView?
    private let paper: UIColor
    private weak var screen: UIViewController?
    private var dragging: Run?
    private var beganAtTopEdge = false

    /// An opening out of `source` onto a page of `paper`, or nothing where what it stands for is not a
    /// cover in full view.
    init?(from source: @escaping @MainActor @Sendable (BookZoom) -> UIView?, paper: UIColor) {
        guard !UIAccessibility.isReduceMotionEnabled, let face = source(.running) else { return nil }
        guard let window = face.window, Self.cover(in: face, seenFrom: window) != nil else { return nil }

        self.source = source
        self.paper = paper
    }

    /// Lets a drag down `screen` shut the book.
    func shuts(_ screen: UIViewController) {
        let drag = UIPanGestureRecognizer(target: self, action: #selector(dragged))

        drag.delegate = self
        drag.maximumNumberOfTouches = 1
        screen.view.addGestureRecognizer(drag)
        self.screen = screen
    }

    /// The cover a face shows and where it stands in `space`, where it is a cover standing wholly on the screen.
    fileprivate static func cover(in face: UIView?, seenFrom space: UIView) -> Cover? {
        guard
            let standIn = face as? BookStandIn,
            standIn.isCover,
            let picture = standIn.image,
            let window = standIn.window,
            standIn.bounds.width > 0
        else { return nil }

        let frame = standIn.convert(standIn.bounds, to: space)

        guard window.bounds.contains(standIn.convert(standIn.bounds, to: window)) else { return nil }

        return Cover(picture: picture, frame: frame, isSeeThrough: standIn.isSeeThrough)
    }

    fileprivate struct Cover {
        let picture: UIImage
        let frame: CGRect
        let isSeeThrough: Bool
    }

    @objc
    private func dragged(_ drag: UIPanGestureRecognizer) {
        // The window's space rather than the screen's, which the shutting scales.
        guard let view = drag.view?.window else { return }

        let moved = drag.translation(in: view)
        let travel = moved.y / (view.bounds.height * Self.fullDrag)
        let velocity = drag.velocity(in: view)

        switch drag.state {
            case .began:
                dragging = Run(source: source, paper: paper, opens: false)
                screen?.dismiss(animated: true)
            case .changed:
                dragging?.follow(grown: 1 - travel, moved: CGVector(dx: moved.x, dy: moved.y))
            case .ended:
                let speed = velocity.y / view.bounds.height
                let shut = speed > Self.flick || (speed > -Self.flick && travel > Self.halfway)

                dragging?.letGo(shut: shut, velocity: CGVector(dx: velocity.x, dy: velocity.y))
                dragging = nil
            case .cancelled, .failed:
                dragging?.letGo(shut: false, velocity: .zero)
                dragging = nil
            default:
                break
        }
    }

    /// How far down the screen, as a share of its height, a drag takes the book down to its cover's size.
    private static let fullDrag: CGFloat = 0.6

    /// Past this share of that the book shuts when let go; before it, it opens again.
    private static let halfway: CGFloat = 0.25

    /// How fast a drag let go has to be, in screen heights a second, to decide by its direction instead.
    private static let flick: CGFloat = 0.5
}

extension BookOpening: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let window = touch.window { beganAtTopEdge = touch.location(in: window).y < window.safeAreaInsets.top }

        return true
    }

    /// Only a drag down, and never one from the top edge, which is the system's.
    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let drag = recognizer as? UIPanGestureRecognizer, !beganAtTopEdge else { return false }

        let velocity = drag.velocity(in: drag.view)

        return velocity.y > abs(velocity.x)
    }

    func gestureRecognizer(
        _ recognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

extension BookOpening: UIViewControllerTransitioningDelegate {
    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        Run(source: self.source, paper: paper, opens: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        dragging ?? Run(source: source, paper: paper, opens: false)
    }

    func interactionControllerForDismissal(
        using animator: UIViewControllerAnimatedTransitioning
    ) -> UIViewControllerInteractiveTransitioning? {
        dragging
    }
}

/// One opening or shutting, run against a clock or by a finger.
@MainActor
private final class Run: NSObject {
    private let source: @MainActor @Sendable (BookZoom) -> UIView?
    private let paper: UIColor
    private let opens: Bool
    private var context: UIViewControllerContextTransitioning?
    private var book: OpeningBook?
    private var open: CGFloat
    /// How far off its own path a finger has moved the book.
    private var shift = CGVector.zero
    private var followed: (grown: CGFloat, moved: CGVector)?
    /// A finger let go before the transition had begun.
    private var lateLetGo: (shut: Bool, velocity: CGVector)?
    private var clock: Clock?

    private struct Clock {
        let link: UIUpdateLink
        let from: CGFloat
        let target: CGFloat
        let seconds: Double
        /// Time the run has spent moving, which a stalled frame adds no more than one frame's worth to.
        var elapsed: Double = 0
        var lastTick: CFTimeInterval?
        /// Where a finger let the book go off its own path, and how fast it was moving it, in points a
        /// second; nothing for a run from rest.
        let letGo: (shift: CGVector, velocity: CGVector)?

        /// How far along the run is at `ran` of its time. A run from rest keeps to time, since the book
        /// eases itself; one a finger let go of only slows into place.
        func share(_ ran: Double) -> Double { letGo == nil ? ran : 1 - pow(1 - ran, 3) }

        /// How far off its path the book stands at `ran`: it carries on as the finger left it and settles
        /// onto the path, along a cubic Hermite from the shift and the finger's speed to rest.
        func shift(_ ran: Double) -> CGVector {
            guard let letGo else { return .zero }

            let run = CGFloat(ran)
            let leaving = 2 * run * run * run - 3 * run * run + 1
            let carrying = (run * run * run - 2 * run * run + run) * CGFloat(seconds)

            return CGVector(
                dx: letGo.shift.dx * leaving + letGo.velocity.dx * carrying,
                dy: letGo.shift.dy * leaving + letGo.velocity.dy * carrying
            )
        }
    }

    init(source: @escaping @MainActor @Sendable (BookZoom) -> UIView?, paper: UIColor, opens: Bool) {
        self.source = source
        self.paper = paper
        self.opens = opens
        open = opens ? 0 : 1
    }

    /// Where the finger has taken the book: grown `grown` of the way to the screen's size, its middle
    /// moved by `moved` from the screen's.
    func follow(grown: CGFloat, moved: CGVector) {
        followed = (min(max(grown, 0), 1), moved)

        guard let context, let book, let followed else { return }

        open = OpeningBook.open(grown: followed.grown)
        shift = book.shift(following: followed.moved, at: open)
        book.draw(open: open, shift: shift)
        context.updateInteractiveTransition(1 - open)
    }

    /// The finger has let go at `velocity`: the book runs on to shut, or back to open.
    func letGo(shut: Bool, velocity: CGVector) {
        guard let context else { return lateLetGo = (shut, velocity) }

        if shut { context.finishInteractiveTransition() } else { context.cancelInteractiveTransition() }

        let carried = CGVector(dx: velocity.dx * Self.flickCarry, dy: velocity.dy * Self.flickCarry)

        run(to: shut ? 0 : 1, letGo: (shift, carried))
    }

    /// Lays the book out and hides the cover it stands for, in the one frame.
    private func begin(_ context: UIViewControllerContextTransitioning) {
        self.context = context

        let container = context.containerView
        let key: UITransitionContextViewKey = opens ? .to : .from

        guard let page = context.view(forKey: key) else { return }

        if opens, let screen = context.viewController(forKey: .to) {
            container.addSubview(page)
            page.frame = context.finalFrame(for: screen)
        }

        let face = source(.running)
        let cover = BookOpening.cover(in: face, seenFrom: container)
        let frame = cover?.frame ?? face.map { $0.convert($0.bounds, to: container) }
        let ground = context.viewController(forKey: opens ? .from : .to)?.view

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        _ = source(.covered)

        // Only a board with nothing printed on it needs what stands behind it drawn in.
        let picture = cover.map { cover in
            guard cover.isSeeThrough, let ground else { return cover.picture }

            return Self.backed(cover.picture, by: ground, at: container.convert(cover.frame, to: ground))
        }

        book = OpeningBook(page: page, in: container, cover: frame, picture: picture, paper: paper)
        book?.draw(open: open)
        CATransaction.commit()
    }

    /// The cover laid over what stands behind it, since a board with no artwork yet is see-through.
    private static func backed(_ picture: UIImage, by ground: UIView, at frame: CGRect) -> UIImage {
        let format = UIGraphicsImageRendererFormat()

        format.scale = picture.scale

        return UIGraphicsImageRenderer(size: frame.size, format: format).image { drawn in
            let bounds = CGRect(origin: .zero, size: frame.size)

            drawn.cgContext.addPath(CoverPrint.board(in: bounds))
            drawn.cgContext.clip()
            drawn.cgContext.saveGState()
            drawn.cgContext.translateBy(x: -frame.minX, y: -frame.minY)
            ground.layer.render(in: drawn.cgContext)
            drawn.cgContext.restoreGState()
            picture.draw(in: bounds)
        }
    }

    private func run(to target: CGFloat, letGo: (shift: CGVector, velocity: CGVector)? = nil) {
        clock?.link.isEnabled = false

        guard let view = context?.containerView else { return }

        // UIKit's own update link: a display link added during a frame misses the next one.
        let link = UIUpdateLink(view: view)
        // A book let go near where it will settle still has the finger's shift to lose.
        let distance = letGo == nil ? abs(target - open) : max(abs(target - open), Self.leastLetGoRun)
        let seconds = OpeningMotion.seconds * Double(distance)

        clock = Clock(link: link, from: open, target: target, seconds: seconds, letGo: letGo)
        link.addAction { [weak self] _, info in self?.ticked(at: info.modelTime) }
        link.requiresContinuousUpdates = true
        link.preferredFrameRateRange = Self.frameRates
        link.isEnabled = true
    }

    private func ticked(at now: TimeInterval) {
        guard var clock else { return }

        // Counted from the first frame drawn, and a frame that ran long adds only a frame: the reader
        // lays itself out as it arrives, and a clock that counted that stall would skip the first steps.
        clock.elapsed += clock.lastTick.map { min(now - $0, Self.longestStep) } ?? 0
        clock.lastTick = now
        self.clock = clock

        let ran = clock.seconds > 0 ? min(clock.elapsed / clock.seconds, 1) : 1

        open = clock.from + (clock.target - clock.from) * CGFloat(clock.share(ran))
        shift = clock.shift(ran)
        book?.draw(open: open, shift: shift)

        guard ran >= 1 else { return }

        clock.link.isEnabled = false
        self.clock = nil
        end()
    }

    /// The screen's own rate where it has one to spare; a motion this large shows every frame dropped.
    private static let frameRates = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)

    /// How much of a flick's speed the book carries on with once let go.
    private static let flickCarry: CGFloat = 0.6

    /// The most one frame may move the run on, however long it took to draw.
    private static let longestStep: CFTimeInterval = 1.0 / 30

    /// The least share of a whole run a book let go by a finger takes to settle.
    private static let leastLetGoRun: CGFloat = 0.4

    /// Puts everything back as the run left it: the screen in place, or the cover on the shelf again.
    private func end() {
        guard let context else { return }

        let finished = !context.transitionWasCancelled

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if !opens, finished { _ = source(.done) }

        book?.remove(withPage: !opens && finished)
        book = nil
        CATransaction.commit()
        context.completeTransition(finished)
        self.context = nil
    }
}

extension Run: UIViewControllerAnimatedTransitioning {
    func transitionDuration(using context: UIViewControllerContextTransitioning?) -> TimeInterval {
        OpeningMotion.seconds
    }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        begin(context)
        run(to: opens ? 1 : 0)
    }
}

extension Run: UIViewControllerInteractiveTransitioning {
    func startInteractiveTransition(_ context: UIViewControllerContextTransitioning) {
        begin(context)

        if let followed { follow(grown: followed.grown, moved: followed.moved) }
        if let lateLetGo { letGo(shut: lateLetGo.shut, velocity: lateLetGo.velocity) }
    }
}
