//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// How far through something the reader is, as a ring, with a tick once it is done.
///
/// One ring for every place that shows progress round a circle. There were two, drawn separately and
/// differing in ways nobody had chosen.
public struct ProgressRing: View {
    /// What the ring is drawn over.
    public enum Ground {
        /// Over artwork nobody has seen, so the ring brings its own backing.
        case artwork
        /// On a surface the app painted, where the track alone reads.
        case surface
    }

    public let progress: Double
    public let isComplete: Bool
    public var ground: Ground
    /// A ring just begun still reads as begun rather than as untouched.
    public var minimumTrim: Double

    public init(progress: Double, isComplete: Bool, ground: Ground = .surface, minimumTrim: Double = 0) {
        self.progress = progress
        self.isComplete = isComplete
        self.ground = ground
        self.minimumTrim = minimumTrim
    }

    private var trim: Double { max(minimumTrim, min(1, max(0, progress))) }

    public var body: some View {
        ZStack {
            if ground == .artwork {
                Circle().fill(.thinMaterial)
            }

            if isComplete {
                Circle().fill(Design.Palette.accent)

                Image(systemName: "checkmark")
                    .font(.system(size: Design.Size.glyph(in: Design.Size.mark), weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .stroke(Design.Surface.edge, lineWidth: Design.Stroke.ring)
                    .padding(Design.Stroke.ring / 2)

                Circle()
                    .trim(from: 0, to: trim)
                    .stroke(
                        Design.Palette.accent,
                        style: StrokeStyle(lineWidth: Design.Stroke.ring, lineCap: .round)
                    )
                    .padding(Design.Stroke.ring / 2)
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: Design.Size.mark, height: Design.Size.mark)
        .accessibilityHidden(true)
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
