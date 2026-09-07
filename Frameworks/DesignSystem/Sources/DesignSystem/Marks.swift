//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// A wedge that fills as something is read, closing to a full disc and a tick once it is done.
///
/// One mark for every place that shows progress round a circle. There were two, drawn separately and
/// differing in ways nobody had chosen.
public struct ProgressMark: View {
    /// What the mark is drawn over.
    public enum Ground {
        /// Over artwork nobody has seen, so the mark brings its own backing.
        case artwork
        /// On a surface the app painted, where the track alone reads.
        case surface
    }

    public let progress: Double
    public let isComplete: Bool
    public var ground: Ground

    /// How far an unfinished wedge is allowed to close.
    ///
    /// A book at 99% swept to 99% is a full disc to the eye, and finishing a book is worth being able
    /// to see. The whole range is scaled into this instead of clipped at the top, so the wedge still
    /// grows with every page rather than stalling near the end.
    ///
    /// Held to a notch rather than a slice: enough that a closed circle means finished, little enough
    /// that a book nearly read looks nearly read.
    private static let widestUnfinished = 0.95

    /// The narrowest a wedge is drawn once there is anything to draw.
    ///
    /// A page into a long book is a fraction of a degree, which is nothing at all at this size. Both
    /// ends of the sweep are held off their extremes for the same reason: started has to look started
    /// and finished has to look finished, and neither can be left to a wedge too thin to see.
    private static let narrowestStarted = 0.06

    public init(progress: Double, isComplete: Bool, ground: Ground = .surface) {
        self.progress = progress
        self.isComplete = isComplete
        self.ground = ground
    }

    /// Nothing read draws nothing. Everything else is scaled into the band between the two limits, so
    /// the wedge grows the whole way without ever reaching either end by accident.
    private var sweep: Double {
        let read = min(1, max(0, progress))

        guard read > 0 else { return 0 }

        return Self.narrowestStarted + read * (Self.widestUnfinished - Self.narrowestStarted)
    }

    public var body: some View {
        ZStack {
            if ground == .artwork {
                Circle().fill(.thinMaterial)
            }

            Circle()
                .fill(Design.Surface.edge)

            if isComplete {
                Circle()
                    .fill(Design.Palette.accent)

                Image(systemName: "checkmark")
                    .font(.system(size: Design.Size.glyph(in: Design.Size.mark), weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Sector(sweep: sweep)
                    .fill(Design.Palette.accent)
            }
        }
        .frame(width: Design.Size.mark, height: Design.Size.mark)
        .accessibilityHidden(true)
    }
}

/// A wedge of a circle, swept clockwise from the top.
struct Sector: Shape {
    let sweep: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)

        path.move(to: centre)
        path.addArc(
            center: centre,
            radius: min(rect.width, rect.height) / 2,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * sweep),
            clockwise: false
        )
        path.closeSubpath()

        return path
    }
}

/// A glyph in a circle, for a mark that sits on artwork.
public struct CircleMark: View {
    public let systemImage: String
    public var tint: Color

    public init(systemImage: String, tint: Color = Design.Palette.neutral) {
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            Circle().fill(.thinMaterial)

            Image(systemName: systemImage)
                .font(.system(size: Design.Size.glyph(in: Design.Size.mark)))
                .foregroundStyle(tint)
        }
        .frame(width: Design.Size.mark, height: Design.Size.mark)
        .accessibilityHidden(true)
    }
}

/// One fact, as a tinted pill: a glyph and a short phrase.
public struct Pill: View {
    /// A pill with no title is its glyph alone.
    public let title: String?
    public let systemImage: String
    public var tint: Color
    /// What VoiceOver reads. A pill with no title has none to fall back on.
    public let label: String

    /// One line of the pill's own text style, which follows Dynamic Type as the text in it does.
    @ScaledMetric(relativeTo: .caption2)
    private var lineHeight: CGFloat = 13

    public init(title: String?, systemImage: String, tint: Color = Design.Palette.neutral, label: String) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.label = label
    }

    public var body: some View {
        HStack(spacing: Design.Space.extraSmall) {
            Image(systemName: systemImage)
                .font(Design.Style.micro)
                .imageScale(.small)

            if let title {
                Text(title)
                    .font(Design.Style.micro)
                    .lineLimit(1)
            }
        }
        // A glyph is shorter than a line of text, so a pill carrying no word would stand smaller
        // than the ones beside it in the same row.
        .frame(minHeight: lineHeight)
        .foregroundStyle(tint)
        .padding(.horizontal, Design.Space.small)
        .padding(.vertical, Design.Space.extraSmall)
        .background(Design.Surface.ground(tint), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

/// A filter the reader can turn on, as a capsule that fills when it is.
public struct FilterChip: View {
    public let title: String
    public let isSelected: Bool
    public let hint: String
    public let action: () -> Void

    public init(title: String, isSelected: Bool, hint: String, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.hint = hint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(Design.Style.label)
                .padding(.horizontal, Design.Space.large)
                .padding(.vertical, Design.Space.small)
                .background(isSelected ? Design.Palette.accent : Design.Surface.fill, in: .capsule)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [ .isButton, .isSelected ] : .isButton)
        .accessibilityHint(hint)
    }
}

/// A volume's place in its series, set in front of the title it belongs to.
///
/// Takes the colour of whatever it stands beside rather than a tint of its own: the number is part of
/// the title, not a fact about the book like the pills are.
public struct SeriesNumber: View {
    public let number: Int

    public init(number: Int) {
        self.number = number
    }

    public var body: some View {
        Text(number, format: .number)
            .font(Design.Style.micro.monospacedDigit())
            .padding(.horizontal, Design.Space.small)
            .padding(.vertical, Design.Space.extraSmall)
            .background(Design.Surface.fill, in: .rect(cornerRadius: Design.Radius.small))
            .accessibilityHidden(true)
    }
}
