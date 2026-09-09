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
    /// Which shelf the book came off, marked on the cover. Nothing marks nothing.
    var origin: CoverOrigin?
    /// True where the author is still writing it, which the cover says rather than the row: it is a
    /// fact about the book, and the badges below are about the reader's standing in it.
    var isOngoing = false

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
                    .frame(height: Design.Size.coverHeight(width: width))
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
            if let origin {
                SourceMark(origin: origin)
                    .padding(Design.Space.extraSmall)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if isOngoing {
                OngoingMark()
                    .padding(Design.Space.extraSmall)
            }
        }
        .accessibilityHidden(true)
        // What shape this cover turned out to be, for a shelf that has to give every book on it the
        // same slot. Nothing is reported until the picture is here to be measured.
        .preference(key: CoverShape.self, value: cover.map { $0.size.height / $0.size.width } ?? 0)
        .task(id: url) {
            guard let url else { return image = nil }

            // The shared cache is emptied when the app goes to the background, so what it holds is
            // taken as this view's own rather than read through it each time it draws.
            if let held = CoverImages.image(for: url) { return image = held }
            guard let loaded = await CoverCache.shared.image(for: url) else { return }

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
/// Which shelf a book came off.
enum CoverOrigin: Equatable {
    /// The service the app signs in to.
    case service
    case litres
    /// Picked out of the files on the device by the reader.
    case file

    var systemImage: String {
        switch self {
            case .service: "cloud.fill"
            case .litres: "bag.fill"
            case .file: "doc.text.fill"
        }
    }

    var name: String {
        switch self {
            case .service: "author.today"
            case .litres: String(localized: "Litres")
            case .file: String(localized: "A file on this device")
        }
    }
}

/// Where a book came from, as a mark on its cover.
struct SourceMark: View {
    let origin: CoverOrigin

    var body: some View {
        CircleMark(systemImage: origin.systemImage)
    }
}

/// A book its author is still writing, as a mark on its cover.
struct OngoingMark: View {
    var body: some View {
        CircleMark(systemImage: "pencil")
    }
}

/// The tallest cover among however many are reporting.
///
/// A shelf gives every book the same slot, and that slot has to be as tall as the tallest picture on it
/// or that one alone would be shrunk to fit. Covers say what shape they are as they load, and whatever
/// is showing them keeps the largest.
struct CoverShape: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
