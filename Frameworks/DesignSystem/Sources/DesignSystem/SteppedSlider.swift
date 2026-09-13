//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// A slider with a step either side of it.
///
/// A setting like this is felt for by dragging and settled by pressing: the drag gets near, and the
/// two steps put it where it was wanted without the finger covering the answer.
public struct SteppedSlider: View {
    @Binding
    public var value: Double

    public let range: ClosedRange<Double>
    /// What the drag moves by.
    public let step: Double
    /// What a press either side moves by, which is a step the reader would notice rather than the
    /// finest one the slider can make.
    public let nudge: Double
    /// Named so a test can drive the slider and VoiceOver can read it.
    public let identifier: String
    public let label: LocalizedStringKey
    /// The value as it is spoken, which the caller knows the units of.
    public let spoken: String

    /// The keys are the caller's, so they resolve against the app's catalogue and not this package's.
    public init(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double,
        nudge: Double,
        identifier: String,
        label: LocalizedStringKey,
        spoken: String
    ) {
        _value = value
        self.range = range
        self.step = step
        self.nudge = nudge
        self.identifier = identifier
        self.label = label
        self.spoken = spoken
    }

    public var body: some View {
        HStack(spacing: Design.Space.medium) {
            press("chevron.left", by: -nudge, named: "Less")

            Slider(value: $value, in: range, step: step)
                .accessibilityIdentifier(identifier)
                .accessibilityLabel(label)
                .accessibilityValue(spoken)

            press("chevron.right", by: nudge, named: "More")
        }
    }

    private func press(_ glyph: String, by amount: Double, named: LocalizedStringKey) -> some View {
        Button {
            value = Self.settled(value + amount, in: range, by: step)
        } label: {
            Image(systemName: glyph)
                .font(.footnote.weight(.semibold))
                .frame(width: Design.Space.large, height: Design.Space.large)
        }
        .buttonStyle(.glass)
        .disabled(amount < 0 ? value <= range.lowerBound : value >= range.upperBound)
        .accessibilityLabel(named)
    }

    /// Held inside the range and on the step, so a tenth of a point added ten times is a point rather
    /// than a point and a hair.
    public static func settled(_ value: Double, in range: ClosedRange<Double>, by step: Double) -> Double {
        let stepped = step > 0 ? (value / step).rounded() * step : value

        return min(max(stepped, range.lowerBound), range.upperBound)
    }
}
