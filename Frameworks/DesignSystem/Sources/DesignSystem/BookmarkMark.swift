//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// A ribbon hanging from the top edge of a cover, notched at its free end, carrying a figure or a glyph.
///
/// It hangs at the end of the reading line along that edge, which `offset(reached:across:)` works out,
/// and carries the same line of shade around its own edge:
///
/// ```swift
/// BookmarkMark(.figure(47), tint: BookmarkMark.reading)
/// BookmarkMark(.glyph("checkmark"), tint: BookmarkMark.read)
/// ```
public struct BookmarkMark: View {
    public enum Face: Hashable, Sendable {
        /// A percentage, set without its sign's room to spare.
        case figure(Int)
        case glyph(String)
    }

    public let face: Face
    public let tint: Color

    public init(_ face: Face, tint: Color) {
        self.face = face
        self.tint = tint
    }

    /// The line under the reading line and around the bookmark, which lifts both off the artwork.
    /// White whatever it is laid on: the mark is a thing on the cover rather than a mark in it, and a
    /// line that changed with the artwork would read as part of the picture.
    public static let shade = Color.white.opacity(0.45)

    /// How deep the mark hangs, the line of shade round its foot included.
    public static let depth = Design.Size.bookmarkHeight + Design.Stroke.readingShade

    /// A ribbon's own red, which says nothing beyond being a bookmark's.
    public static let reading = Color(red: 0.8, green: 0.22, blue: 0.2)
    public static let read = Design.Palette.positive
    /// Opaque, since the ribbon hangs over the artwork.
    public static let waiting = Color(.systemGray)

    public var body: some View {
        ZStack {
            // The same line that runs under the reading line, drawn round the ribbon: the stroke
            // straddles its edge and the ribbon is laid over the inner half of it.
            BookmarkShape()
                .stroke(Self.shade, lineWidth: Design.Stroke.readingShade * 2)

            BookmarkShape()
                .fill(tint)
                .overlay(BookmarkFace(face))
        }
        .frame(width: Design.Size.bookmark, height: Design.Size.bookmarkHeight)
        // Room for the half of the stroke that falls outside the ribbon.
        .padding(Design.Stroke.readingShade)
        .accessibilityHidden(true)
    }

    /// The line read and the bookmark hanging at its end, as one outline.
    ///
    /// One shape rather than two: a line drawn round each of them would cross where they meet, and the
    /// ribbon would read as something laid on the line rather than the end of it.
    nonisolated public static func silhouette(reached: Double, across width: CGFloat) -> CGPath {
        let stand = offset(reached: reached, across: width)
        let ribbon = BookmarkShape()
            .path(
                in: CGRect(x: stand, y: 0, width: Design.Size.bookmark, height: Design.Size.bookmarkHeight)
            )
            .cgPath
        // The line runs as far as the bookmark and no further: past it, it would read as a second
        // thing hanging off the far side of the ribbon.
        guard stand > 0 else { return ribbon }

        return ribbon.union(CGPath(
            rect: CGRect(x: 0, y: 0, width: stand, height: Design.Stroke.readingLine),
            transform: nil
        ))
    }

    /// How far the reading line runs across a cover of this width. It starts at the cover's own edge and
    /// is cut by the cover's shape, as everything else printed on the board is.
    nonisolated public static func line(reached: Double, across width: CGFloat) -> CGFloat {
        width * min(1, max(0, reached))
    }

    /// How far along the cover the bookmark hangs: just past the end of the line read, so the line shows
    /// in full, and held off either end so that neither a book unopened nor one read through hangs its
    /// bookmark on a corner.
    ///
    /// It stands further in at the start than at the end. A bookmark at the start has the whole cover
    /// behind it and room to spare; one at the end is as far along as the reader can get, and holding
    /// it further in would read as something still left.
    nonisolated public static func offset(reached: Double, across width: CGFloat) -> CGFloat {
        let run = line(reached: reached, across: width)
        let last = max(first, width - Design.Size.bookmark - Design.Space.extraSmall)

        return max(first, min(run, last))
    }

    nonisolated private static let first = Design.Space.small
}

/// What a bookmark carries, set in white on the ribbon: a percentage, or a glyph.
public struct BookmarkFace: View {
    public let face: BookmarkMark.Face

    public init(_ face: BookmarkMark.Face) {
        self.face = face
    }

    public var body: some View {
        content
            .foregroundStyle(.white)
            // A nudge below the middle of the ribbon, which the notch takes a bite out of.
            .offset(y: Design.Space.nudge)
            // Clear of the notch, so a figure sits in the part of the ribbon that is all there.
            .frame(width: Design.Size.bookmark, height: Design.Size.bookmarkHeight - BookmarkShape.notch)
            .frame(width: Design.Size.bookmark, height: Design.Size.bookmarkHeight, alignment: .top)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch face {
            case let .figure(percent):
                Text(verbatim: "\(percent)%")
                    .font(Design.Style.spine)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            case let .glyph(systemImage):
                Image(systemName: systemImage)
                    .font(.system(size: Design.Style.spineSize, weight: .bold))
        }
    }
}

/// The line read and the bookmark at its end, as one shape across a cover of the width it is given.
public struct ReadingSilhouette: Shape {
    public let reached: Double

    public init(reached: Double) {
        self.reached = reached
    }

    public func path(in rect: CGRect) -> Path {
        Path(BookmarkMark.silhouette(reached: reached, across: rect.width))
    }
}

/// A bookmark's outline: a strip with a V cut into its lower end.
public struct BookmarkShape: Shape {
    /// How deep the V is cut, as a share of the ribbon's width.
    public static let notch = Design.Size.bookmark * 0.3

    public init() {}

    public func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - Self.notch))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
