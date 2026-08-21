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
struct PageTurnView<Page: View>: View {
    let pageCount: Int

    @Binding
    var index: Int

    /// Whether the chapter either side exists, and what to do once the turn onto it commits.
    var hasPageBefore = false
    var hasPageAfter = false
    var onPastEnd: () -> Void = {}
    var onPastStart: () -> Void = {}
    /// A tap in the dead zone between the two turning thirds.
    var onMiddleTap: () -> Void = {}

    @ViewBuilder
    let page: (Int) -> Page

    private enum Turn {
        case forward
        case backward
    }

    @State
    private var turn: Turn?

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

    private static var commitThreshold: CGFloat { 0.3 }
    private static var flickVelocity: CGFloat { 120 }
    /// A flick against the turn this small still cancels it.
    private static var reverseFlickVelocity: CGFloat { 20 }
    /// How far the finger travels while the incoming page closes the gap between the screen edge and it.
    private static var catchDistance: CGFloat { 80 }
    /// How far the page behind draws back, as a fraction of its size, once it is fully covered.
    private static var recession: CGFloat { 0.05 }
    private static var dimming: CGFloat { 0.22 }

    /// A queued turn runs faster, so a burst of taps reads as pages stacking rather than a slow crawl.
    private var turnDuration: Double { queued != 0 ? 0.09 : 0.22 }

    var body: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { width = max(1, $0) })
        .gesture(drag)
        .onTapGesture(coordinateSpace: .local) { location in
            // Both outer thirds turn forward; the middle third is a dead zone so a reader can rest a
            // thumb there without losing their place.
            let third = width / 3

            guard location.x < third || location.x > width - third else { return onMiddleTap() }

            advance()
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Next page"), advance)
        .accessibilityAction(named: Text("Previous page"), retreat)
        .accessibilityAction(named: Text("Show or hide the reader controls"), onMiddleTap)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let translation = value.translation.width

                if turn == nil {
                    queued = 0

                    if translation < 0, isReachable(index + 1) {
                        turn = .forward
                    } else if translation > 0, isReachable(index - 1) {
                        turn = .backward
                    } else {
                        return
                    }
                }

                guard let turn else { return }

                // Measuring against the turn's own direction lets a reversed finger unwind the turn.
                progress =
                    switch turn {
                        case .forward: forwardProgress(value)
                        case .backward: min(1, max(0, translation / width))
                    }
            }
            .onEnded { value in
                guard let turn else { return }

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
    /// It leaves the right edge, closes the gap to the finger over ``catchDistance``, and from there
    /// its edge sits under the finger and moves with it. Sliding it in by the finger's travel alone
    /// would leave the page's edge wherever the drag happened to start, which reads as pushing the page
    /// rather than pulling it.
    private func forwardProgress(_ value: DragGesture.Value) -> CGFloat {
        let gap = max(0, width - value.startLocation.x)
        let travelled = max(0, value.startLocation.x - value.location.x)
        let edge = value.location.x + gap * exp(-travelled / Self.catchDistance)
        return min(1, max(0, 1 - edge / width))
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
