//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// A paged container where the incoming page slides *over* the outgoing one, tracking the finger.
///
/// The whole effect comes from one rule: **page `n + 1` always sits above page `n`**. Turning forward
/// slides page `n + 1` in from the right edge; turning back slides that same page off to the right and
/// uncovers page `n`. One offset drives both directions, so a half-finished turn in either direction can
/// be reversed without any special handling.
struct PageTurnView<Page: View>: View {
    let pageCount: Int

    @Binding
    var index: Int

    /// Called when the reader turns past the last page or before the first — the reader uses these to
    /// cross into the neighbouring chapter.
    var onPastEnd: () -> Void = {}
    var onPastStart: () -> Void = {}

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

    /// A queued turn runs faster, so a burst of taps reads as pages stacking rather than a slow crawl.
    private var turnDuration: Double { queued != 0 ? 0.12 : 0.25 }

    var body: some View {
        ZStack {
            if let turn, let lower = lowerIndex(turn), let upper = upperIndex(turn) {
                page(lower)

                page(upper)
                    .background(Color.clear)
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.25), radius: 8, x: -3, y: 0)
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

            guard location.x < third || location.x > width - third else { return }

            advance()
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Next page"), advance)
        .accessibilityAction(named: Text("Previous page"), retreat)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let translation = value.translation.width

                if turn == nil {
                    queued = 0

                    if translation < 0, index + 1 < pageCount {
                        turn = .forward
                    } else if translation > 0, index > 0 {
                        turn = .backward
                    } else {
                        return
                    }
                }

                guard let turn else { return }

                // Measuring against the turn's own direction lets a reversed finger unwind the turn.
                let travelled = turn == .forward ? -translation : translation
                progress = min(1, max(0, travelled / width))
            }
            .onEnded { value in
                let translation = value.translation.width
                let predicted = value.predictedEndTranslation.width

                guard let turn else { return endAtBoundary(translation: translation) }

                let velocity = turn == .forward ? -(predicted - translation) : (predicted - translation)
                let shouldCommit = progress > Self.commitThreshold || velocity > Self.flickVelocity
                finish(turn, committing: shouldCommit)
            }
    }

    /// A decisive swipe with nowhere left to go in this chapter hands over to the next one.
    private func endAtBoundary(translation: CGFloat) {
        guard abs(translation) > width * Self.commitThreshold else { return }

        if translation < 0, index + 1 >= pageCount {
            onPastEnd()
        } else if translation > 0, index == 0 {
            onPastStart()
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

    /// Starts a turn, or hands over to the neighbouring chapter when there is nowhere left to go.
    private func begin(_ direction: Turn) {
        switch direction {
            case .forward where index + 1 >= pageCount:
                queued = 0
                return onPastEnd()
            case .backward where index == 0:
                queued = 0
                return onPastStart()
            default:
                break
        }

        turn = direction
        finish(direction, committing: true)
    }

    private func finish(_ turn: Turn, committing: Bool) {
        withAnimation(.easeOut(duration: turnDuration), completionCriteria: .logicallyComplete) {
            progress = committing ? 1 : 0
        } completion: {
            if committing {
                switch turn {
                    case .forward: index = min(index + 1, pageCount - 1)
                    case .backward: index = max(index - 1, 0)
                }
            }

            self.turn = nil
            progress = 0
            drainQueue()
        }
    }

    /// Runs the next queued turn, if the reader got ahead of the animation.
    private func drainQueue() {
        guard queued != 0 else { return }

        let direction: Turn = queued > 0 ? .forward : .backward
        queued -= queued > 0 ? 1 : -1
        begin(direction)
    }

    private func lowerIndex(_ turn: Turn) -> Int? {
        let candidate = turn == .forward ? index : index - 1
        return (0 ..< pageCount).contains(candidate) ? candidate : nil
    }

    private func upperIndex(_ turn: Turn) -> Int? {
        let candidate = turn == .forward ? index + 1 : index
        return (0 ..< pageCount).contains(candidate) ? candidate : nil
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
