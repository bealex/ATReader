//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// A cover drawn the way the reader draws every other picture in a book.
///
/// The title page is a page of the book, so the cover on it answers to the same two rules the plates
/// inside do: colour art fades into a dark page, and everything follows the page's own colours once the
/// reader has asked it to. ``CoverImage`` is the plain one, for the library and the shelves, where
/// there is no page tint to answer to.
struct PagePicture: View {
    let url: URL?
    var width: CGFloat = 150
    let palette: PagePalette

    @State
    private var picture: PageImage?

    var body: some View {
        Group {
            if let picture, picture.size.width > 0 {
                let height = width * picture.size.height / picture.size.width

                Canvas { context, size in
                    context.withCGContext { drawing in
                        picture.draw(in: CGRect(origin: .zero, size: size), palette: palette, into: drawing)
                    }
                }
                .frame(width: width, height: height)
            } else {
                Color.clear.frame(width: width, height: width * 1.5)
            }
        }
        .clipShape(.rect(cornerRadius: width * 0.08))
        .overlay {
            RoundedRectangle(cornerRadius: width * 0.08)
                .strokeBorder(Color(palette.foreground).opacity(0.15), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url else { return picture = nil }
            guard let loaded = await CoverCache.shared.image(for: url) else { return }

            picture = BookImages.shared.prepare(loaded, key: "cover:\(url.absoluteString)")
        }
    }
}
