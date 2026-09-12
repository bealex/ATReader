//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// A bar that fills to a number, and slides back and forth while there isn't one yet.
///
/// One bar rather than a spinner and then a bar: a wait that starts before anything can be counted and
/// ends counted is still one wait, and swapping the shape halfway reads as two.
public struct ProgressBar: View {
    public let value: Double?
    public var tint: Color

    @State
    private var slid = false

    /// How much of the track the sliding piece covers while there is nothing to measure.
    private static let share: CGFloat = 0.35
    private static let slide = Animation.easeInOut(duration: 0.85).repeatForever(autoreverses: true)

    public init(value: Double?, tint: Color = Design.Palette.accent) {
        self.value = value
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let run = width * Self.share

            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.18))

                if let value {
                    Capsule()
                        .fill(tint)
                        .frame(width: width * min(1, max(0, value)))
                        .animation(.easeOut(duration: 0.2), value: value)
                } else {
                    Capsule()
                        .fill(tint)
                        .frame(width: run)
                        .offset(x: slid ? width - run : 0)
                        .animation(Self.slide, value: slid)
                        .onAppear { slid = true }
                }
            }
        }
        .frame(height: Design.Space.extraSmall)
        .accessibilityHidden(true)
    }
}
