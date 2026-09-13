//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import DesignSystem
import SwiftUI

/// A book cover, printed the way the shelf prints one: its artwork cut to the board, the board's edge,
/// the crease it is bound along and the shade of the shelf at its foot.
///
/// `CoverPrint` does the drawing, so a book on a page and the same book on the shelf are one picture
/// rather than two drawings that have to be kept in step. Backed by ``CoverCache`` rather than
/// `AsyncImage`: covers are downsampled once and kept on disk, so scrolling back through a list costs
/// nothing and a second launch shows them immediately.
struct CoverImage: View {
    let url: URL?
    var width: CGFloat = Design.Size.cover
    /// Where the reader is in the book: a line along the top edge and a bookmark hanging from it.
    var reading: ReadingMark?
    /// Where a zoom grows a screen out of this cover, for the one screen that opens a book from it.
    var anchor: CoverAnchor?

    @Environment(\.colorScheme)
    private var scheme

    @State
    private var face: UIImage?

    /// The artwork this cover is of, which says what shape the board comes out.
    private var artwork: UIImage? { url.flatMap(CoverImages.image(for:)) }

    /// How tall the board stands: the artwork's own shape where it is at hand, and the commonest shape
    /// until then, so a row doesn't jump when the picture lands.
    private var height: CGFloat {
        guard let artwork, artwork.size.width > 0 else { return Design.Size.coverHeight(width: width) }

        return Design.Size.coverHeight(width: width, ratio: artwork.size.height / artwork.size.width)
    }

    var body: some View {
        Group {
            if let face {
                Image(uiImage: face)
                    .resizable()
                    .transition(.opacity)
            } else {
                // The bare board until this book's own face is printed, which is what the shelf stands.
                Image(uiImage: CoverPrint.blank(isDark: scheme == .dark))
                    .resizable()
                    .overlay { if url == nil { emptyMark } }
            }
        }
        .frame(width: width, height: height)
        .background {
            if let anchor { CoverAnchorView(anchor: anchor, face: face) }
        }
        .overlay(alignment: .topLeading) {
            if let reading { mark(reading) }
        }
        // Over the mark: the binding's shadow falls on what is drawn on the board as it does on the artwork.
        .overlay(alignment: .topLeading) {
            if reading != nil {
                Image(uiImage: CoverPrint.binding(isDark: scheme == .dark))
                    .resizable()
                    .frame(width: CoverPrint.bindingWidth, height: BookmarkMark.depth)
            }
        }
        // Cut with the board, which is square along its binding and rounded at its fore-edge.
        .clipShape(CoverBoard())
        .accessibilityHidden(true)
        // What shape this cover turned out to be, for a shelf that has to give every book on it the
        // same slot. Nothing is reported until the picture is here to be measured.
        .preference(key: CoverShape.self, value: artwork.map { $0.size.height / $0.size.width } ?? 0)
        .task(id: Printing(url: url, width: width, isDark: scheme == .dark)) {
            await press(url)
        }
    }

    /// What a printed face is asked for. A cover is printed again when the book, its size or the room's
    /// light changes, and at no other time.
    private struct Printing: Equatable {
        let url: URL?
        let width: CGFloat
        let isDark: Bool
    }

    /// Prints this book's face, fetching the artwork if the device hasn't got it.
    private func press(_ url: URL?) async {
        guard let url else { return face = nil }

        // The shared cache is emptied when the app goes to the background, so the picture is taken as
        // this view's own rather than read through it each time it draws.
        var found = CoverImages.image(for: url)

        if found == nil { found = await CoverCache.shared.image(for: url) }

        guard let held = found else { return }

        CoverImages.remember(held, for: url)

        let order = CoverPrint.Order(
            url: url,
            size: CGSize(
                width: width,
                height: Design.Size.coverHeight(width: width, ratio: held.size.height / held.size.width)
            ),
            isDark: scheme == .dark
        )

        guard let printed = await CoverPrint.printed(order) else { return }

        withAnimation(.easeOut(duration: ArrivalMotion.fadeSeconds)) { face = printed }
    }

    /// How far the reader has got, as one shape: the line along the top edge and the bookmark at its
    /// end, with a line of shade round the whole of it. Drawn inside the cover's own shape, so it is
    /// cut where the cover is.
    private func mark(_ reading: ReadingMark) -> some View {
        let silhouette = ReadingSilhouette(reached: reading.reached)

        return ZStack(alignment: .topLeading) {
            // Under the shape rather than round it: the half of the stroke that falls inside is covered.
            silhouette
                .stroke(BookmarkMark.shade, lineWidth: Design.Stroke.readingShade * 2)

            silhouette
                .fill(reading.tint)

            BookmarkFace(reading.face)
                .offset(x: BookmarkMark.offset(reached: reading.reached, across: width))
        }
        .frame(width: width, height: BookmarkMark.depth, alignment: .topLeading)
    }

    /// What a book with no artwork at all shows, on the bare board.
    private var emptyMark: some View {
        Image(systemName: "book.closed")
            .font(.system(size: width * 0.3))
            .foregroundStyle(.tertiary)
    }
}

/// The shape a board is cut to, for clipping anything laid over one.
struct CoverBoard: Shape {
    func path(in rect: CGRect) -> Path { Path(CoverPrint.board(in: rect)) }
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
