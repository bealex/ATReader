//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import UIKit

/// Turns one sheet onto the next, the incoming sheet sliding *over* the outgoing one and tracking the
/// finger.
///
/// The sheet after always stands above the one before it: turning forward slides it in from the edge,
/// turning back slides the current one off and uncovers the one before. One offset drives both, so a
/// half-finished turn either way can be reversed.
///
/// `sheet` is asked for `-1`, `0` and `1`: the sheet before, the one in front of the reader and the
/// one after. A turn that lands calls `onForward` or `onBack`, and the owner moves the book on and
/// calls ``reload()``.
@MainActor
public final class PageTurner: UIView {
    public var sheet: (Int) -> UIView? = { _ in nil }
    /// Whether there is a sheet either side to turn onto, cut yet or not.
    public var hasSheetBefore = false
    public var hasSheetAfter = false
    public var onForward: () -> Void = {}
    public var onBack: () -> Void = {}
    /// A tap on the page itself, offered before the turning zones see it. True where it was taken.
    public var onPageTap: (CGPoint) -> Bool = { _ in false }
    /// A finger held on the page and then drawn across it, which is how text is picked out.
    public var onPickOut: (CGPoint, CGPoint) -> Void = { _, _ in }
    public var onPickedOut: () -> Void = {}
    /// A tap in the dead zone between the two turning thirds.
    public var onMiddleTap: () -> Void = {}
    /// The moment a turn takes hold, by tap or by finger.
    public var onTurnStarted: () -> Void = {}
    /// Something stands over the page, and every touch belongs to it.
    public var isCovered = false
    /// The book is read from the right, so forward is the other way.
    public var readsRightToLeft = false
    /// A tap on the left turns forward, as one on the right does. Off, the left goes back a page.
    public var advancesOnLeftTap = true

    private enum Turn {
        case forward
        case backward
    }

    /// A turn let go of, until it lands; the id tells a finished animation from a superseded one.
    private struct Settle {
        let id: Int
        let turn: Turn
        let commits: Bool
    }

    private let stage = UIView()
    private let dim = UIView()
    private var turn: Turn?
    /// `0` is at rest, `1` fully onto the neighbouring sheet.
    private var progress: CGFloat = 0
    private var settling: Settle?
    private var settleCount = 0
    /// Turns asked for while one was running. Positive is forward.
    private var queued = 0
    private var isPickingOut = false
    private var heldAt: CGPoint = .zero
    private var hasDragged = false
    /// True while the sheet is still behind the finger, closing on it faster than the finger moves.
    private var isCatchingUp = false
    /// Where the finger had the sheet at its last move.
    private var fingerProgress: CGFloat = 0
    /// Which sheets stood beneath and above at the last arrangement.
    private var roles: (beneath: UIView?, upper: UIView?)
    private var overscroll: CGFloat = 0
    private var shown: [UIView] = []
    private var arrangedSize: CGSize = .zero
    /// Asked for while a turn was settling, whose animation a fresh arrangement would cut short.
    private var needsReload = false

    override public init(frame: CGRect) {
        super.init(frame: frame)

        clipsToBounds = true
        stage.frame = bounds
        stage.autoresizingMask = [ .flexibleWidth, .flexibleHeight ]
        addSubview(stage)

        dim.backgroundColor = .black
        dim.alpha = 0
        dim.isUserInteractionEnabled = false
        dim.isAccessibilityElement = false

        let pan = HorizontalPan(target: self, action: #selector(dragged))
        let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed))
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))

        pan.page = self
        pan.maximumNumberOfTouches = 1
        pan.onTouchDown = { [weak self] in self?.hasDragged = false }
        press.minimumPressDuration = Self.pressDuration
        // Lifting a finger that picked words out is not a tap as well.
        tap.require(toFail: press)

        for recognizer in [ pan, press, tap ] as [UIGestureRecognizer] {
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            addGestureRecognizer(recognizer)
        }

        accessibilityIdentifier = "reader.page"
        accessibilityCustomActions = baseActions

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(resigned),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Actions offered beside the turner's own, as notes on the page are.
    public var extraActions: [UIAccessibilityCustomAction] = [] {
        didSet { accessibilityCustomActions = baseActions + extraActions }
    }

    private var baseActions: [UIAccessibilityCustomAction] {
        [
            UIAccessibilityCustomAction(name: String(localized: "Next page", bundle: .module)) { [weak self] _ in
                self?.advance()
                return true
            },
            UIAccessibilityCustomAction(name: String(localized: "Previous page", bundle: .module)) { [weak self] _ in
                self?.retreat()
                return true
            },
            UIAccessibilityCustomAction(
                name: String(localized: "Show or hide the reader controls", bundle: .module)
            ) { [weak self] _ in
                self?.onMiddleTap()
                return true
            },
        ]
    }

    /// Asks for the sheets again, after the book moved or a sheet changed.
    public func reload() {
        guard settling == nil else { return needsReload = true }

        arrange()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        guard bounds.size != arrangedSize else { return }

        arrangedSize = bounds.size
        arrange()
    }

    // MARK: - Drawing

    private var width: CGFloat { max(1, bounds.width) }
    private var mirror: CGFloat { readsRightToLeft ? -1 : 1 }

    /// Puts the sheets where the turn has them: the one beneath drawn back and dimmed by as much as the
    /// one above covers it.
    ///
    /// The sheets either side stay in the window at no opacity, so they are set and drawn before a turn
    /// brings them in rather than as it does.
    private func arrange() {
        let beneath = sheet(turn.flatMap(lowerStep) ?? 0)
        let upper = turn.flatMap(upperStep).flatMap(sheet)
        let wanted = [ beneath, upper ].compactMap(\.self)
        let waiting = [ -1, 0, 1 ].compactMap(sheet).filter { !wanted.contains($0) }
        let order = waiting + [ beneath, dim, upper ].compactMap(\.self)
        let rolesChanged = beneath !== roles.beneath || upper !== roles.upper

        roles = (beneath, upper)

        // Which sheets are drawn and in what order is never animated, only where they stand.
        UIView.performWithoutAnimation {
            // Put back in order only where it changed: moving a view that is mid-turn stops its animation.
            if stage.subviews != order {
                for view in stage.subviews where !order.contains(view) { view.removeFromSuperview() }
                for (index, view) in order.enumerated() { stage.insertSubview(view, at: index) }
            }

            for view in order where view !== dim { place(view) }

            for view in waiting {
                view.alpha = 0
                view.transform = .identity
                view.layer.shadowOpacity = 0
            }

            for view in wanted { view.alpha = 1 }

            dim.frame = stage.bounds
            beneath?.layer.shadowOpacity = 0

            if let upper {
                upper.layer.shadowColor = UIColor.black.cgColor
                upper.layer.shadowOpacity = Self.shadowOpacity
                upper.layer.shadowRadius = Self.shadowRadius
                upper.layer.shadowOffset = CGSize(width: -Self.shadowReach * mirror, height: 0)
                upper.layer.shadowPath = UIBezierPath(rect: upper.bounds).cgPath
            }

            // A sheet taking a part in a turn starts where the turn does, not where it was left.
            if rolesChanged { position(beneath: beneath, upper: upper, at: 0) }
        }

        shown = wanted
        position(beneath: beneath, upper: upper, at: progress)
        stage.transform = CGAffineTransform(translationX: overscroll * mirror, y: 0)
    }

    /// Stands the two sheets of a turn where `progress` of it has them.
    private func position(beneath: UIView?, upper: UIView?, at progress: CGFloat) {
        let covered = turn.map { coverage($0, at: progress) } ?? 0

        beneath?.transform = CGAffineTransform(scaleX: 1 - Self.recession * covered, y: 1 - Self.recession * covered)
        dim.alpha = Self.dimming * covered

        guard let upper, let turn else { return }

        upper.transform = CGAffineTransform(translationX: offset(turn, at: progress) * mirror, y: 0)
    }

    private func place(_ view: UIView) {
        let size = stage.bounds.size

        view.bounds = CGRect(origin: .zero, size: size)
        view.center = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    // MARK: - Touches

    @objc
    private func tapped(_ tap: UITapGestureRecognizer) {
        // A short flick lifts inside a tap's tolerance, and has turned the page already.
        guard !hasDragged, !isCovered else { return }

        let location = tap.location(in: self)

        // A note's marker is far smaller than the zone it stands in, so the page answers first.
        guard !onPageTap(location) else { return }

        let third = width / 3

        if location.x < third { return advancesOnLeftTap ? advance() : retreat() }

        guard location.x > width - third else { return onMiddleTap() }

        advance()
    }

    @objc
    private func pressed(_ press: UILongPressGestureRecognizer) {
        let point = press.location(in: self)

        switch press.state {
            case .began:
                guard !isCovered else { return }

                isPickingOut = true
                heldAt = point
                // A finger can travel the eight points that start a turn inside the time a press takes.
                cancelTurn()
                onPickOut(point, point)
            case .changed:
                guard isPickingOut else { return }

                onPickOut(heldAt, point)
            case .ended, .cancelled, .failed:
                guard isPickingOut else { return }

                isPickingOut = false
                onPickedOut()
            default:
                break
        }
    }

    @objc
    private func dragged(_ pan: HorizontalPan) {
        let translation = pan.translation(in: self).x * mirror
        let velocity = pan.velocity(in: self).x * mirror

        switch pan.state {
            case .began, .changed:
                hasDragged = true
                follow(translation: translation, at: pan.location(in: self))
            case .ended, .cancelled, .failed:
                let predicted = translation + velocity * Self.projection

                letGo(translation: translation, predicted: predicted)
            default:
                break
        }
    }

    private func follow(translation: CGFloat, at location: CGPoint) {
        guard !isPickingOut, !isCovered else { return }

        // A turn still running is not this finger's to steer: it lands, and the next move takes a page.
        if settling != nil {
            queued = 0
            return land()
        }

        if turn == nil {
            queued = 0

            if translation < 0, isReachable(1) {
                turn = .forward
            } else if translation > 0, isReachable(-1) {
                turn = .backward
            } else {
                overscroll = rubberBand(translation)
                return arrange()
            }

            onTurnStarted()
            progress = 0
            fingerProgress = fingerTarget(translation: translation, at: location)
            isCatchingUp = true
            return arrange()
        }

        let target = fingerTarget(translation: translation, at: location)

        if isCatchingUp {
            catchUp(to: target)
        } else {
            progress = target
        }

        fingerProgress = target
        arrange()
    }

    /// Where the finger has the sheet, `0…1` of the turn.
    private func fingerTarget(translation: CGFloat, at location: CGPoint) -> CGFloat {
        switch turn {
            case .forward: forwardProgress(at: location)
            case .backward: min(1, max(0, translation / width))
            case nil: 0
        }
    }

    /// Moves a sheet that is behind the finger as far as the finger moved and more, the more the further
    /// behind it is, so it closes the gap as the finger goes and then keeps the finger's own pace.
    ///
    /// Only the finger moves it: a finger held still holds the sheet where it is.
    private func catchUp(to target: CGFloat) {
        let moved = target - fingerProgress
        let behind = max(0, target - progress)

        progress += moved > 0 ? moved * (1 + Self.catchUp * behind) : moved
        progress = min(max(progress, 0), target)

        guard (target - progress) * width < Self.caughtUp else { return }

        progress = target
        isCatchingUp = false
    }

    private func letGo(translation: CGFloat, predicted: CGFloat) {
        isCatchingUp = false

        guard !isPickingOut, !isCovered, let turn else { return releaseOverscroll() }

        let travelled = turn == .forward ? -translation : translation
        let velocity = turn == .forward ? -(predicted - translation) : (predicted - translation)

        finish(turn, committing: commits(travelled: travelled, velocity: velocity))
    }

    /// A flick back cancels however far the page had come; otherwise the finger's own travel decides.
    private func commits(travelled: CGFloat, velocity: CGFloat) -> Bool {
        if velocity < -Self.reverseFlickVelocity { return false }
        if velocity > Self.flickVelocity { return true }

        return travelled / width > Self.commitThreshold
    }

    /// Where the incoming sheet has got to, held ``grip`` inside its own leading edge.
    private func forwardProgress(at location: CGPoint) -> CGFloat {
        let across = readsRightToLeft ? width - location.x : location.x

        return min(1, max(0, 1 - (across - Self.grip) / width))
    }

    @objc
    private func resigned() { cancelTurn() }

    // MARK: - Turning

    public func advance() {
        guard turn == nil else { return queued += 1 }

        begin(.forward)
    }

    public func retreat() {
        guard turn == nil else { return queued -= 1 }

        begin(.backward)
    }

    private func begin(_ direction: Turn) {
        guard
            isReachable(direction == .forward ? 1 : -1)
        else {
            queued = 0
            return bounce(direction)
        }

        turn = direction
        // Laid out at its starting place first, so the animation has somewhere to run from.
        progress = 0
        arrange()
        onTurnStarted()
        finish(direction, committing: true)
    }

    private func finish(_ turn: Turn, committing: Bool) {
        settleCount += 1

        let id = settleCount

        settling = Settle(id: id, turn: turn, commits: committing)
        progress = committing ? 1 : 0

        UIView.animate(
            withDuration: queued != 0 ? Self.quickTurn : Self.turn,
            delay: 0,
            options: [ .beginFromCurrentState, .allowUserInteraction, .curveEaseOut ],
            animations: arrange,
            completion: { [weak self] _ in
                // A finger that arrived first has landed it already.
                guard self?.settling?.id == id else { return }

                self?.land()
            }
        )
    }

    /// Puts the turn that was let go of where it was going, without waiting for it to get there.
    private func land() {
        guard let settling else { return }

        self.settling = nil
        needsReload = false

        if settling.commits {
            switch settling.turn {
                case .forward: onForward()
                case .backward: onBack()
            }
        }

        rest()
        drainQueue()
    }

    private func cancelTurn() {
        releaseOverscroll()

        guard turn != nil else { return }

        queued = 0
        isCatchingUp = false
        settling = nil
        rest()
    }

    /// Stands the sheet still at once, whatever was moving it.
    private func rest() {
        for view in shown { view.layer.removeAllAnimations() }

        dim.layer.removeAllAnimations()
        progress = 0
        turn = nil
        UIView.performWithoutAnimation(arrange)
    }

    private func drainQueue() {
        guard queued != 0 else { return }

        let direction: Turn = queued > 0 ? .forward : .backward

        queued -= queued > 0 ? 1 : -1
        begin(direction)
    }

    /// Nudges the sheet and lets it spring back, for a tap at an end of the book.
    private func bounce(_ direction: Turn) {
        guard overscroll == 0 else { return }

        overscroll = width * Self.bounceReach * (direction == .forward ? -1 : 1)
        UIView.animate(
            withDuration: Self.bounceOut,
            delay: 0,
            options: [ .curveEaseOut, .allowUserInteraction ],
            animations: arrange,
            completion: { [weak self] _ in self?.releaseOverscroll() }
        )
    }

    /// Gives less the harder the sheet is pulled, the way a list does at its end.
    private func rubberBand(_ distance: CGFloat) -> CGFloat {
        let limit = width * Self.overscrollLimit

        return distance * limit / (limit + abs(distance))
    }

    private func releaseOverscroll() {
        guard overscroll != 0 else { return }

        overscroll = 0
        UIView.animate(
            springDuration: Self.springBack,
            bounce: Self.springBounce,
            options: [ .allowUserInteraction ],
            animations: arrange
        )
    }

    private func isReachable(_ step: Int) -> Bool {
        switch step {
            case -1: hasSheetBefore
            case 1: hasSheetAfter
            default: true
        }
    }

    private func lowerStep(_ turn: Turn) -> Int? {
        let candidate = turn == .forward ? 0 : -1

        return isReachable(candidate) ? candidate : nil
    }

    private func upperStep(_ turn: Turn) -> Int? {
        let candidate = turn == .forward ? 1 : 0

        return isReachable(candidate) ? candidate : nil
    }

    private func coverage(_ turn: Turn, at progress: CGFloat) -> CGFloat {
        switch turn {
            case .forward: progress
            case .backward: 1 - progress
        }
    }

    /// How far the upper sheet is pushed aside: all the way at rest turning forward, none turning back.
    private func offset(_ turn: Turn, at progress: CGFloat) -> CGFloat {
        switch turn {
            case .forward: width * (1 - progress)
            case .backward: width * progress
        }
    }

    private static let pressDuration: TimeInterval = 0.22
    private static let commitThreshold: CGFloat = 0.3
    /// In points past the finger's travel, as `projection` of a second carries it.
    private static let flickVelocity: CGFloat = 30
    private static let reverseFlickVelocity: CGFloat = 20
    private static let projection: CGFloat = 0.1
    private static let grip: CGFloat = 20
    /// How much faster than the finger a sheet behind it moves, for each whole width it is behind: half
    /// a width behind, it moves at six times the finger's pace.
    private static let catchUp: CGFloat = 10
    /// Near enough, in points, for the sheet to be under the finger.
    private static let caughtUp: CGFloat = 0.5
    private static let overscrollLimit: CGFloat = 0.2
    private static let springBack: TimeInterval = 0.35
    private static let springBounce: CGFloat = 0.45
    private static let recession: CGFloat = 0.05
    private static let dimming: CGFloat = 0.22
    private static let shadowOpacity: Float = 0.35
    private static let shadowRadius: CGFloat = 7
    private static let shadowReach: CGFloat = 5
    private static let bounceReach: CGFloat = 0.035
    private static let bounceOut: TimeInterval = 0.12
    private static let turn: TimeInterval = 0.22
    /// A queued turn runs faster, so a burst of taps reads as sheets stacking.
    private static let quickTurn: TimeInterval = 0.09
}

extension PageTurner: UIGestureRecognizerDelegate {
    public func gestureRecognizer(
        _ recognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

/// A pan that takes a drag across the page and fails on one up or down it, which is the book's way out.
final class HorizontalPan: UIPanGestureRecognizer {
    /// The page, which decides whether a touch is this one's and is the space it reports in.
    weak var page: UIView?
    var onTouchDown: (() -> Void)?

    /// How far a finger travels before its direction is read, under the pan's own threshold.
    private static let slop: CGFloat = 6

    private var start: CGPoint?

    override func reset() {
        super.reset()
        start = nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        // A second finger joining a drag leaves the state past possible, and is not a touch of its own.
        if state == .possible { onTouchDown?() }

        super.touchesBegan(touches, with: event)

        guard
            let page,
            let touch = touches.first,
            page.window != nil,
            !isUnderASheet(page)
        else { return state = .failed }

        start = touch.location(in: page)
    }

    /// True where something is presented over the page, since a sheet covers it without moving it.
    ///
    /// Only this screen's own controllers are asked, by walking parents: the responder chain runs out
    /// through whatever presented the reader, which is presenting it.
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
        // Read before the pan is given the touches: a flick arrives as one move long enough to begin it.
        if state == .possible, let page, let start, let now = touches.first?.location(in: page) {
            let across = abs(now.x - start.x)
            let along = abs(now.y - start.y)

            if max(across, along) > Self.slop, along > across { return state = .failed }
        }

        super.touchesMoved(touches, with: event)
    }
}
