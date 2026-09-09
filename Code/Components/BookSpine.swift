//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import DesignSystem
import SwiftUI

/// A book already read, stood on its edge the way a finished book stands on a shelf.
///
/// A series read to its end is a wall of artwork saying nothing the reader needs: what they want from
/// those books is that they are behind them, and which volume each was. A spine says both in a fifth
/// of the width, so what is left to read stays on the same screen.
struct BookSpine: View {
    let work: Book
    let number: Int?
    let title: String
    let height: CGFloat
    /// What a cover measures here, which is what a spine's own thickness is worked out against.
    let coverWidth: CGFloat

    @State
    private var image: UIImage?

    @Environment(\.colorScheme)
    private var scheme

    /// Drawn in the first frame where the cover is already decoded, and fetched where it isn't. A
    /// spine that only read the cache stayed grey until something else on the shelf loaded the same
    /// picture.
    private var cover: UIImage? { image ?? work.coverURL.flatMap(CoverImages.image(for:)) }

    private var isDark: Bool { scheme == .dark }

    /// How light a spine may get, and how dark.
    ///
    /// The colour under it is somebody else's artwork: a pale cover washes out to nothing on a dark
    /// shelf, and a dark one swallows the writing on a light shelf. So the colour is held to one side
    /// of a line rather than scaled towards it, which keeps the hue and loses only the extremes.
    private var limit: Color { Color(white: isDark ? 0.45 : 0.72) }

    /// Grey on a dark shelf, near-black on a light one. Writing printed onto a binding is never the
    /// brightest thing on it.
    private var ink: Color { isDark ? .white.opacity(0.58) : .black.opacity(0.8) }

    private var wash: Color { isDark ? .black.opacity(0.15) : .white.opacity(0.15) }

    /// The shadow a raised letter casts, below it, and the light caught along its top edge. Together
    /// they are what makes the writing sit proud of the spine rather than lie printed flat on it.
    private var relief: Color { isDark ? .black.opacity(0.6) : .black.opacity(0.3) }

    private var highlight: Color { isDark ? .white.opacity(0.3) : .white.opacity(0.85) }

    private var width: CGFloat { Self.width(of: work, cover: coverWidth) }

    var body: some View {
        ZStack {
            ground
            binding
            writing
        }
        .frame(width: width, height: height)
        .clipShape(.rect(cornerRadius: Design.Radius.spine))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(number.map { "Volume \($0), \(work.title), read" } ?? "\(work.title), read")
        .task(id: work.coverURL) {
            guard let url = work.coverURL else { return }

            // Held here even when the shared cache already has it. That cache is emptied when the app
            // goes to the background, and a spine drawing straight out of it came back grey.
            if let held = CoverImages.image(for: url) { return image = held }
            guard let loaded = await CoverCache.shared.image(for: url) else { return }

            CoverImages.remember(loaded, for: url)
            image = loaded
        }
    }

    /// The book's own cover, thrown far enough out of focus to be colour rather than picture, and
    /// taken down far enough for the writing to sit on it.
    private var ground: some View {
        Group {
            if let cover {
                // Deepened rather than greyed: taking a cover down with black alone walks its colour
                // out of it, so the colour is pushed up as the brightness comes down.
                Image(uiImage: cover)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: Design.Size.spineBlur)
                    .saturation(1.35)
                    .brightness(isDark ? -0.18 : 0.08)
                    // A ceiling on a dark shelf and a floor on a light one, taken per channel so a
                    // colour keeps its hue and gives up only what stood past the line.
                    .overlay(Rectangle().fill(limit).blendMode(isDark ? .darken : .lighten))
            } else {
                Design.Surface.fill
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .overlay(wash)
        .overlay(curve)
    }

    /// What makes it read as a rounded spine rather than a coloured strip: both edges fall away into
    /// shadow and the middle catches the light.
    private var curve: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.38), location: 0),
                .init(color: .clear, location: 0.28),
                .init(color: .white.opacity(0.13), location: 0.46),
                .init(color: .clear, location: 0.68),
                .init(color: .black.opacity(0.38), location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// How a bound book is put together, which is what the eye reads as a spine rather than a bar: a
    /// groove where each cover hinges on, a pale head where the paper shows, and a dark foot.
    private var binding: some View {
        ZStack {
            HStack(spacing: 0) {
                groove
                Spacer(minLength: 0)
                groove
            }
            .padding(.horizontal, Design.Space.extraSmall)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(.white.opacity(0.3))
                    .frame(height: Design.Stroke.hairline)

                Spacer(minLength: 0)

                Rectangle()
                    .fill(.black.opacity(0.4))
                    .frame(height: Design.Stroke.hairline)
            }
        }
    }

    private var groove: some View {
        Rectangle()
            .fill(.black.opacity(0.35))
            .frame(width: Design.Stroke.hairline)
    }

    /// Set along the spine, read from the foot upwards, with the volume nearest the bottom edge.
    private var writing: some View {
        HStack(spacing: Design.Space.small) {
            if let number {
                Text(number, format: .number)
                    .font(Design.Style.spine.monospacedDigit())
                    .opacity(0.75)
            }

            // Narrow and small, the way a spine is set: the width belongs to the book, and what is
            // printed on it has to live in whatever is left.
            Text(title)
                .font(Design.Style.spine)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .foregroundStyle(ink)
        // Stamped rather than printed: light along the top of each letter and its shadow below.
        //
        // Both offsets are given in the writing's own space, which the spine then turns on its side,
        // so what is written here as sideways lands as up and down once it is stood on end.
        .shadow(color: relief, radius: 0, x: -Design.Stroke.hairline)
        .shadow(color: highlight, radius: 0, x: Design.Stroke.hairline)
        .padding(.horizontal, Design.Space.medium)
        .frame(width: height, height: width)
        .rotationEffect(.degrees(-90))
    }

    /// How thick a book stands: its own length, between a floor that leaves room for the writing and
    /// a ceiling that stops one long book crowding out the covers beside it.
    ///
    /// A shelf of one width says every book is the same size, which no shelf of real books is.
    static func width(of work: Book, cover: CGFloat = Design.Size.gridCover) -> CGFloat {
        let thinnest = max(Design.Size.spine, cover * 0.2)
        let thickest = cover * 0.32

        guard let length = work.textLength, length > 0 else { return (thinnest + thickest) / 2 }

        let share = min(1, max(0, (Double(length) - Self.shortBook) / (Self.longBook - Self.shortBook)))

        return thinnest + (thickest - thinnest) * share
    }

    /// The lengths a spine is measured between. Below the first every book is as thin as the writing
    /// allows; above the second, as thick as the shelf allows.
    private static let shortBook: Double = 250_000
    private static let longBook: Double = 1_400_000
}

/// A volume between two the reader holds that they don't. Drawn in the same shape as whatever the
/// shelf is showing, so a gap keeps its place in the run rather than being listed elsewhere.
struct MissingSlot: View {
    let number: Int
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Design.Radius.spine)
                .fill(Design.Surface.fill)

            RoundedRectangle(cornerRadius: Design.Radius.spine)
                .strokeBorder(Design.Surface.edge, lineWidth: Design.Stroke.hairline)

            Text(number, format: .number)
                .font(Design.Style.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(width > Design.Size.spine ? 0 : -90))
        }
        .frame(width: width, height: height)
        .opacity(0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume \(number), not in your library")
    }
}
