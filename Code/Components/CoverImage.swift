//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// A book cover with a placeholder that keeps the layout stable while the image loads.
///
/// Backed by ``CoverCache`` rather than `AsyncImage`: covers are downsampled once and kept on disk, so
/// scrolling back through a list costs nothing and a second launch shows them immediately.
struct CoverImage: View {
    let url: URL?
    var width: CGFloat = 72
    /// How far into the book the reader is, drawn as a ring on the cover itself.
    var progress: Double?
    /// True where the book came from a file rather than the service, which the cover says quietly.
    var isLocal = false

    @State
    private var image: UIImage?

    /// Drawn in the first frame when the cover is already decoded, so a view rebuilt under a new
    /// identity — what a page turn does to the title page — doesn't blink through the placeholder.
    private var cover: UIImage? { image ?? url.flatMap(CoverImages.image(for:)) }

    var body: some View {
        Group {
            if let cover {
                // Fitted, not filled: the service's covers are not all the same shape, and filling a
                // box of one shape with an image of another cuts the edges off.
                Image(uiImage: cover)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .transition(.opacity)
            } else {
                placeholder
                    .frame(height: width * 1.5)
            }
        }
        .frame(width: width)
        .clipShape(.rect(cornerRadius: width * 0.08))
        .overlay {
            RoundedRectangle(cornerRadius: width * 0.08)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        }
        .overlay(alignment: .bottomTrailing) {
            if let progress, progress > 0 {
                ReadingProgressRing(progress: progress)
                    .padding(4)
            }
        }
        .overlay(alignment: .topLeading) {
            if isLocal {
                FileMark()
                    .padding(4)
            }
        }
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url else { return image = nil }
            guard cover == nil, let loaded = await CoverCache.shared.image(for: url) else { return }

            CoverImages.remember(loaded, for: url)
            withAnimation(.easeOut(duration: 0.15)) { image = loaded }
        }
    }

    private var placeholder: some View {
        ZStack {
            Rectangle()
                .fill(Color(.secondarySystemFill))

            Image(systemName: "book.closed")
                .font(.system(size: width * 0.3))
                .foregroundStyle(.tertiary)
        }
    }
}

/// A book that came from a file rather than from the service.
///
/// Smaller than ``ReadingProgressRing`` and set in the opposite corner, because where a book came from
/// is a footnote beside how far through it the reader is.
struct FileMark: View {
    private static let size: CGFloat = 19

    var body: some View {
        ZStack {
            Circle()
                .fill(.thinMaterial)

            Image(systemName: "doc.text.fill")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(width: Self.size, height: Self.size)
        .accessibilityHidden(true)
    }
}

/// How far through a book the reader is, as a ring with the figure inside it. Always 30pt across,
/// whatever the cover it sits on: it is a badge rather than a part of the artwork.
struct ReadingProgressRing: View {
    let progress: Double

    static let size: CGFloat = 30

    /// The ring is inset by half its own width, so its outer edge lands on the badge's edge and no
    /// backing shows around it.
    private static let lineWidth: CGFloat = 3.2

    var body: some View {
        ZStack {
            Circle()
                .fill(.thinMaterial)

            Circle()
                .stroke(Color.primary.opacity(0.15), lineWidth: Self.lineWidth)
                .padding(Self.lineWidth / 2)

            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .padding(Self.lineWidth / 2)
                .rotationEffect(.degrees(-90))

            label
                .foregroundStyle(.primary)
        }
        .frame(width: Self.size, height: Self.size)
        .accessibilityHidden(true)
    }

    /// A book read to its end says so with a tick, which is the mark the eye finds without reading it.
    @ViewBuilder
    private var label: some View {
        if progress >= WorkSummary.readThreshold {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
        } else {
            Text(progress.formatted(.percent.precision(.fractionLength(0))))
                .font(.system(size: 7.2, weight: .semibold).monospacedDigit())
                .minimumScaleFactor(0.7)
        }
    }
}

/// Whether a book sits in the reader's library, as a badge on its cover. Sized to match
/// ``ReadingProgressRing`` so the two sit as a pair on the same cover.
struct LibraryMark: View {
    let inLibrary: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(.thinMaterial)

            Image(systemName: inLibrary ? "book.fill" : "book")
                .font(.system(size: 14))
                .foregroundStyle(inLibrary ? Color.accentColor : Color.secondary)
        }
        .frame(width: ReadingProgressRing.size, height: ReadingProgressRing.size)
        .accessibilityHidden(true)
    }
}
