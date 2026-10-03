//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import UIKit

/// A bar that fills to a number, with a piece running along it while there isn't one yet.
///
/// One bar rather than a spinner and then a bar: a wait that starts before anything can be counted and
/// ends counted is still one wait, and swapping the shape halfway reads as two.
public struct ProgressBar: View {
    public let value: Double?
    public var tint: Color
    /// The part not yet filled. A faint wash of the tint unless said otherwise.
    public var track: Color?

    /// How much of the track the sliding piece covers while there is nothing to measure.
    private static let share: CGFloat = 0.35
    /// Seconds for the piece to run in at the leading end and out at the trailing one.
    private static let sweep: TimeInterval = 1.4

    public init(value: Double?, tint: Color = Design.Palette.accent, track: Color? = nil) {
        self.value = value
        self.tint = tint
        self.track = track
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let run = width * Self.share

            ZStack(alignment: .leading) {
                Capsule().fill(track ?? tint.opacity(0.18))

                if let value {
                    Capsule()
                        .fill(tint)
                        .frame(width: width * min(1, max(0, value)))
                        .animation(.easeOut(duration: 0.2), value: value)
                } else {
                    // Driven by the clock rather than a repeating animation, which would also carry
                    // any layout change around the bar along with it.
                    TimelineView(.animation) { timeline in
                        Capsule()
                            .fill(tint)
                            .frame(width: run)
                            .offset(x: (width + run) * Self.progress(at: timeline.date) - run)
                    }
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: Design.Space.extraSmall)
        .accessibilityHidden(true)
    }

    /// How far through its run the sliding piece is, at a steady pace: easing would slow it most where
    /// it is half off the track.
    private static func progress(at date: Date) -> CGFloat {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: sweep) / sweep
    }
}

/// ``ProgressBar`` for a view drawn by UIKit: the same capsule, filled to a number.
@MainActor
public final class ProgressBarView: UIView {
    public var value: Double = 0 { didSet { setNeedsLayout() } }
    public var tint: UIColor = .tintColor { didSet { fill.backgroundColor = tint.cgColor } }
    public var track: UIColor = .clear { didSet { layer.backgroundColor = track.cgColor } }

    private let fill = CALayer()

    override public init(frame: CGRect) {
        super.init(frame: frame)

        layer.addSublayer(fill)
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override public var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Design.Space.extraSmall)
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        let radius = bounds.height / 2

        layer.cornerRadius = radius
        fill.cornerRadius = radius
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * min(1, max(0, value)), height: bounds.height)
    }
}
