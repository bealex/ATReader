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

    @State
    private var image: UIImage?

    private var height: CGFloat { width * 1.5 }

    /// Drawn in the first frame when the cover is already decoded, so a view rebuilt under a new
    /// identity — what a page turn does to the title page — doesn't blink through the placeholder.
    private var cover: UIImage? { image ?? url.flatMap(CoverImages.image(for:)) }

    var body: some View {
        Group {
            if let cover {
                Image(uiImage: cover)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
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

/// How far through a book the reader is, as a ring with the figure inside it. Always 30pt across,
/// whatever the cover it sits on: it is a badge rather than a part of the artwork.
struct ReadingProgressRing: View {
    let progress: Double

    static let size: CGFloat = 30

    var body: some View {
        ZStack {
            Circle()
                .fill(.thinMaterial)

            Circle()
                .stroke(Color.primary.opacity(0.15), lineWidth: 3)
                .padding(2)

            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .padding(2)
                .rotationEffect(.degrees(-90))

            Text(progress.formatted(.percent.precision(.fractionLength(0))))
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .minimumScaleFactor(0.7)
                .foregroundStyle(.primary)
        }
        .frame(width: Self.size, height: Self.size)
        .accessibilityHidden(true)
    }
}
