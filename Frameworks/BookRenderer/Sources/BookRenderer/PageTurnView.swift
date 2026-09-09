//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// A paged container where the incoming page slides *over* the outgoing one, tracking the finger.
///
/// The whole effect comes from one rule: page `n + 1` always sits above page `n`. Turning forward slides
/// page `n + 1` in from the right edge; turning back slides that same page off to the right and uncovers
/// page `n`. One offset drives both directions, so a half-finished turn in either direction can be
/// reversed without any special handling.
///
/// `page` is asked for `-1` and for `pageCount` as well when a neighbouring chapter exists: the turn that
/// crosses a chapter boundary shows the page it is about to land on, so the swap happens invisibly under
/// the animation.
public struct PageTurnView<Page: View>: View {
    public let pageCount: Int

    @Binding
    public var index: Int

    /// Whether the chapter either side exists, and what to do once the turn onto it commits.
    public var hasPageBefore = false
    public var hasPageAfter = false
    public var onPastEnd: () -> Void = {}
    public var onPastStart: () -> Void = {}
    /// A tap on the page itself, offered before the turning zones see it. True where it was taken.
    public var onPageTap: (CGPoint) -> Bool = { _ in false }
    /// A finger held on the page and then drawn across it, which is how text is picked out. The page
    /// stops turning for as long as this is going on.
    public var onPickOut: (CGPoint, CGPoint) -> Void = { _, _ in }
    public var onPickedOut: () -> Void = {}
    /// True while text is picked out and something is being decided about it. The page holds still:
    /// a finger moving over a page in this state is working on the words, not asking for the next one.
    public var isChoosing = false
    /// A tap in the dead zone between the two turning thirds.
    public var onMiddleTap: () -> Void = {}
    /// The moment a turn takes hold, by tap or by finger.
    public var onTurnStarted: () -> Void = {}

    @ViewBuilder
    public let page: (Int) -> Page

    public init(
        pageCount: Int,
        index: Binding<Int>,
        hasPageBefore: Bool = false,
        hasPageAfter: Bool = false,
        onPastEnd: @escaping () -> Void = {},
        onPastStart: @escaping () -> Void = {},
        onPageTap: @escaping (CGPoint) -> Bool = { _ in false },
        onPickOut: @escaping (CGPoint, CGPoint) -> Void = { _, _ in },
        onPickedOut: @escaping () -> Void = {},
        isChoosing: Bool = false,
        onMiddleTap: @escaping () -> Void = {},
        onTurnStarted: @escaping () -> Void = {},
        @ViewBuilder page: @escaping (Int) -> Page
    ) {
        self.pageCount = pageCount
        _index = index
        self.hasPageBefore = hasPageBefore
        self.hasPageAfter = hasPageAfter
        self.onPastEnd = onPastEnd
        self.onPastStart = onPastStart
        self.onPageTap = onPageTap
        self.onPickOut = onPickOut
        self.onPickedOut = onPickedOut
        self.isChoosing = isChoosing
        self.onMiddleTap = onMiddleTap
        self.onTurnStarted = onTurnStarted
        self.page = page
    }

    @Environment(\.scenePhase)
    private var scenePhase

    private enum Turn {
        case forward
        case backward
    }

    @State
    private var turn: Turn?

    /// True while a finger is drawing text out of the page, which is not a turn however far it moves.
    @State
    private var isPickingOut = false

    /// Where the finger was when the press was held long enough to count.
    @State
    private var heldAt: CGPoint = .zero

    /// `0` is the resting state, `1` is fully committed to the neighbouring page.
    @State
    private var progress: CGFloat = 0

    @State
    private var width: CGFloat = 1

    /// Turns asked for while one was already running. Positive is forward, negative is back.
    ///
    /// Tapping faster than a turn animates has to keep up rather than drop the extra taps, so each one
    /// lands here and the queue drains as soon as the running turn commits. Pages then stack through in
    /// quick succession and settle on the page the reader actually asked for.
    @State
    private var queued = 0

    /// When the current drag took hold of a page, so the page's run in from the screen edge can be
    /// animated and the tracking that follows cannot be.
    @State
    private var grabbedAt: Date?

    /// How far the page has been pulled past the end of the book, or before its start.
    @State
    private var overscroll: CGFloat = 0

    private static var commitThreshold: CGFloat { 0.3 }
    private static var flickVelocity: CGFloat { 120 }
    /// A flick against the turn this small still cancels it.
    private static var reverseFlickVelocity: CGFloat { 20 }
    /// How far inside its leading edge the incoming page is held.
    private static var grip: CGFloat { 20 }
    /// How long the page takes to come in from the screen edge and meet the finger.
    private static var grabDuration: Double { 0.3 }
    /// The share of the width a pull past the end can reach, however hard it is pulled.
    private static var overscrollLimit: CGFloat { 0.2 }
    private static var springBack: Animation { .spring(response: 0.35, dampingFraction: 0.55) }
    /// How far the page behind draws back, as a fraction of its size, once it is fully covered.
    private static var recession: CGFloat { 0.05 }
    private static var dimming: CGFloat { 0.22 }

    /// A queued turn runs faster, so a burst of taps reads as pages stacking rather than a slow crawl.
    private var turnDuration: Double { queued != 0 ? 0.09 : 0.22 }

    public var body: some View {
        ZStack {
            if let turn, let lower = lowerIndex(turn), let upper = upperIndex(turn) {
                let covered = coverage(turn)

                page(lower)
                    .scaleEffect(1 - Self.recession * covered)
                    .overlay(Color.black.opacity(Self.dimming * covered).accessibilityHidden(true))

                page(upper)
                    .background(Color.clear)
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.35), radius: 14, x: -5, y: 0)
                    .offset(x: offset(turn))
            } else {
                page(index)
            }
        }
        .offset(x: overscroll)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { width = max(1, $0) })
        .gesture(drag)
        // Watched rather than caught: everything else on the page still answers its own taps.
        .overlay { press }
        .onTapGesture(coordinateSpace: .local) { location in
            // With something picked out, the layer over the page answers taps and the page holds its
            // place. A tap here as well would put the aside away and turn the page in one go.
            guard !isChoosing else { return }
            // Something on the page itself answers first. A note's marker is far smaller than the
            // zone it stands in, so the zones would swallow every tap meant for one.
            guard !onPageTap(location) else { return }

            // Both outer thirds turn forward; the middle third is a dead zone so a reader can rest a
            // thumb there without losing their place.
            let third = width / 3

            guard location.x < third || location.x > width - third else { return onMiddleTap() }

            advance()
        }
        .onChange(of: scenePhase) { _, phase in
            // A turn half-way through when the app leaves the screen has no gesture left to finish it.
            if phase != .active { cancelTurn() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Next page", bundle: .module), advance)
        .accessibilityAction(named: Text("Previous page", bundle: .module), retreat)
        .accessibilityAction(named: Text("Show or hide the reader controls", bundle: .module), onMiddleTap)
    }

    /// A finger held still long enough to mean it starts picking text out, there and then.
    ///
    /// The words light up under the finger rather than when it comes up, so what is about to be taken
    /// can be seen while it is still being chosen.
    private var press: some View {
        PagePressGesture(
            onBegan: { point in
                isPickingOut = true
                heldAt = point
                // A turn may already be under way: a finger can travel the eight points that start one
                // inside the time a press takes to be held. Picking text out is what was meant.
                cancelTurn()
                onPickOut(point, point)
            },
            onMoved: { point in
                guard isPickingOut else { return }

                onPickOut(heldAt, point)
            },
            onEnded: {
                guard isPickingOut else { return }

                isPickingOut = false
                onPickedOut()
            }
        )
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // A finger picking text out, or moving over a page with something already picked, is
                // not turning it however far it travels.
                guard !isPickingOut, !isChoosing else { return }

                let translation = value.translation.width

                if turn == nil {
                    queued = 0
                    grabbedAt = value.time

                    if translation < 0, isReachable(index + 1) {
                        turn = .forward
                    } else if translation > 0, isReachable(index - 1) {
                        turn = .backward
                    } else {
                        // Nowhere to go. The page gives a little, and springs back when the finger lifts.
                        overscroll = rubberBand(translation)
                        return
                    }

                    onTurnStarted()
                }

                guard let turn else { return }

                // Measuring against the turn's own direction lets a reversed finger unwind the turn.
                let target: CGFloat =
                    switch turn {
                        case .forward: forwardProgress(value)
                        case .backward: min(1, max(0, translation / width))
                    }

                // The incoming page has to come in from the screen edge to meet the finger. Animating
                // the first moments of the drag carries it there, and re-targeting an animation already
                // running keeps that smooth however fast the finger is moving.
                guard isGrabbing(at: value.time) else { return progress = target }

                withAnimation(.easeInOut(duration: Self.grabDuration)) { progress = target }
            }
            .onEnded { value in
                guard !isPickingOut, !isChoosing else { return releaseOverscroll() }
                guard let turn else { return releaseOverscroll() }

                let translation = value.translation.width
                let predicted = value.predictedEndTranslation.width
                let travelled = turn == .forward ? -translation : translation
                let velocity = turn == .forward ? -(predicted - translation) : (predicted - translation)
                finish(turn, committing: commits(travelled: travelled, velocity: velocity))
            }
    }

    /// Whether the turn lands.
    ///
    /// A flick back cancels it however far the page had already come, because the reader changing their
    /// mind is the whole point of the gesture. Otherwise the finger's own travel decides, rather than
    /// how far the page has come: the incoming page moves faster than the finger while it catches up.
    private func commits(travelled: CGFloat, velocity: CGFloat) -> Bool {
        if velocity < -Self.reverseFlickVelocity { return false }
        if velocity > Self.flickVelocity { return true }

        return travelled / width > Self.commitThreshold
    }

    /// Where the incoming page has got to, as `0…1`.
    ///
    /// The page is held ``grip`` inside its own leading edge, so the finger sits on the page it is
    /// pulling rather than pushing one along from a distance.
    private func forwardProgress(_ value: DragGesture.Value) -> CGFloat {
        min(1, max(0, 1 - (value.location.x - Self.grip) / width))
    }

    /// True while the page is still on its way to the finger.
    private func isGrabbing(at time: Date) -> Bool {
        guard let grabbedAt else { return false }

        return time.timeIntervalSince(grabbedAt) < Self.grabDuration
    }

    /// Gives less the harder the page is pulled, the way a list does at its end.
    private func rubberBand(_ distance: CGFloat) -> CGFloat {
        let limit = width * Self.overscrollLimit
        return distance * limit / (limit + abs(distance))
    }

    private func releaseOverscroll() {
        guard overscroll != 0 else { return }

        withAnimation(Self.springBack) { overscroll = 0 }
    }

    /// Drops a turn in flight and leaves the reader on the page they were on.
    private func cancelTurn() {
        releaseOverscroll()

        guard turn != nil else { return }

        queued = 0
        grabbedAt = nil

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            progress = 0
            turn = nil
        }
    }

    private func advance() {
        guard turn == nil else { return queued += 1 }

        begin(.forward)
    }

    private func retreat() {
        guard turn == nil else { return queued -= 1 }

        begin(.backward)
    }

    private func begin(_ direction: Turn) {
        let target = direction == .forward ? index + 1 : index - 1

        guard
            isReachable(target)
        else {
            queued = 0
            return
        }

        turn = direction
        onTurnStarted()
        finish(direction, committing: true)
    }

    private func finish(_ turn: Turn, committing: Bool) {
        withAnimation(.easeOut(duration: turnDuration), completionCriteria: .logicallyComplete) {
            progress = committing ? 1 : 0
        } completion: {
            if committing { commit(turn) }

            self.turn = nil
            progress = 0
            drainQueue()
        }
    }

    /// Lands the turn. Crossing out of the chapter hands over to the reader, which swaps in the chapter
    /// whose page is already on screen.
    private func commit(_ turn: Turn) {
        switch turn {
            case .forward where index + 1 < pageCount: index += 1
            case .forward: onPastEnd()
            case .backward where index > 0: index -= 1
            case .backward: onPastStart()
        }
    }

    /// Runs the next queued turn, if the reader got ahead of the animation.
    private func drainQueue() {
        guard queued != 0 else { return }

        let direction: Turn = queued > 0 ? .forward : .backward
        queued -= queued > 0 ? 1 : -1
        begin(direction)
    }

    /// Pages `-1` and `pageCount` exist only when there is a chapter to cross into.
    private func isReachable(_ candidate: Int) -> Bool {
        switch candidate {
            case -1: hasPageBefore
            case pageCount: hasPageAfter
            default: (0 ..< pageCount).contains(candidate)
        }
    }

    private func lowerIndex(_ turn: Turn) -> Int? {
        let candidate = turn == .forward ? index : index - 1
        return isReachable(candidate) ? candidate : nil
    }

    private func upperIndex(_ turn: Turn) -> Int? {
        let candidate = turn == .forward ? index + 1 : index
        return isReachable(candidate) ? candidate : nil
    }

    /// How much of the page behind the turning page covers, `0…1`. It draws back and darkens by this
    /// much, so the page in front reads as the one nearer the reader whichever way the turn is going.
    private func coverage(_ turn: Turn) -> CGFloat {
        switch turn {
            case .forward: progress
            case .backward: 1 - progress
        }
    }

    /// How far the upper page is pushed right: fully off-screen at rest when turning forward, flush at
    /// rest when turning back.
    private func offset(_ turn: Turn) -> CGFloat {
        switch turn {
            case .forward: width * (1 - progress)
            case .backward: width * progress
        }
    }
}
