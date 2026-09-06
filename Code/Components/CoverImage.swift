//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import DesignSystem
import SwiftUI

/// A book cover with a placeholder that keeps the layout stable while the image loads.
///
/// Backed by ``CoverCache`` rather than `AsyncImage`: covers are downsampled once and kept on disk, so
/// scrolling back through a list costs nothing and a second launch shows them immediately.
struct CoverImage: View {
    let url: URL?
    var width: CGFloat = Design.Size.cover
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
                    .resizable().scaledToFit()
                    .transition(.opacity)
            } else {
                placeholder
                    .frame(height: width * 1.5)
            }
        }
        .frame(width: width)
        .clipShape(.rect(cornerRadius: Design.Radius.cover(width: width)))
        .overlay {
            RoundedRectangle(cornerRadius: Design.Radius.cover(width: width))
                .strokeBorder(Design.Surface.edge, lineWidth: Design.Stroke.hairline)
        }
        .overlay(alignment: .bottomTrailing) {
            if let progress, progress > 0 {
                ProgressMark(progress: progress, isComplete: progress >= Book.readThreshold, ground: .artwork)
                    .padding(Design.Space.extraSmall)
            }
        }
        .overlay(alignment: .topLeading) {
            if isLocal {
                FileMark()
                    .padding(Design.Space.extraSmall)
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
                .fill(Design.Surface.fill)

            Image(systemName: "book.closed")
                .font(.system(size: width * 0.3))
                .foregroundStyle(.tertiary)
        }
    }
}

/// A book that came from a file rather than from the service.
struct FileMark: View {
    var body: some View {
        CircleMark(systemImage: "doc.text.fill")
    }
}

/// Whether a book sits in the reader's library, as a mark on its cover.
struct LibraryMark: View {
    let inLibrary: Bool

    var body: some View {
        CircleMark(
            systemImage: inLibrary ? "book.fill" : "book",
            tint: inLibrary ? Design.Palette.accent : Design.Palette.neutral
        )
    }
}
