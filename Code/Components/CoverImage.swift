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

    @State
    private var image: UIImage?

    private var height: CGFloat { width * 1.5 }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
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
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url else { return image = nil }
            guard let loaded = await CoverCache.shared.image(for: url) else { return }

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
