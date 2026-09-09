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
    /// shelf, and a near-black one swallows the writing on a light shelf. The line is drawn per
    /// channel, which is also how a colour is drained of itself: a deep red held to a floor of three
    /// quarters comes out the same grey as a deep blue, since each of its channels is raised to the
    /// same figure. So on a light shelf the floor sits low enough to catch only what is nearly black,
    /// and the lifting is done by brightness, which moves a colour without flattening it.
    private var limit: Color { Color(white: isDark ? 0.45 : 0.35) }

    /// Grey on a dark shelf, near-black on a light one. Writing printed onto a binding is never the
    /// brightest thing on it.
    private var ink: Color { isDark ? .white.opacity(0.58) : .black.opacity(0.8) }

    private var wash: Color { isDark ? .black.opacity(0.15) : .white.opacity(0.06) }

    /// How thick the line at the head is drawn.
    ///
    /// A hairline is half a point, which lands on a pixel and a half: where it falls at the very top
    /// of the spine it covers more of that pixel than the same line does at the foot, and reads as the
    /// thicker of the two. On a dark shelf it is a pale paper edge and can carry the weight; on a
    /// light one it is the same black as the foot, and has to be drawn thinner to look the same.
    private var headline: CGFloat { isDark ? Design.Stroke.hairline : Design.Stroke.hairline / 2 }

    /// The shadow inside a letter pressed into the spine, along its top edge, and the light caught on
    /// the lower lip of the impression. Together they sink the writing into the binding rather than
    /// standing it on top: type on a spine is stamped, and a stamp goes in.
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
                    .saturation(isDark ? 1.35 : 1.7)
                    .brightness(isDark ? -0.18 : 0.14)
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

    private var curve: some View { SpineCurve() }

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

            // Head and foot. On a dark shelf they are a pale paper edge over a dark one; on a light
            // shelf both go dark, since a pale spine swallows a pale line and each edge has to sit
            // against its own ground.
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isDark ? .white.opacity(0.3) : .black.opacity(0.4))
                    .frame(height: headline)

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
            if let number { SpinePlate(number: number) }

            // Narrow and small, the way a spine is set: the width belongs to the book, and what is
            // printed on it has to live in whatever is left.
            Text(title)
                .font(Design.Style.spine)
                .lineLimit(1)
                .truncationMode(.tail)
                // Half a point to the left of the plate below it, once the spine is stood on end.
                // The writing is laid out sideways and then turned, and a turn of a quarter takes
                // what is written here as up onto the screen as left.
                .offset(y: -Design.Stroke.hairline)

            Spacer(minLength: 0)
        }
        .foregroundStyle(ink)
        // Pressed in rather than raised: the shadow falls along the top of each letter, where the
        // light cannot reach into the impression, and the lit edge sits below it.
        //
        // Both offsets are given in the writing's own space, which the spine then turns on its side,
        // so what is written here as sideways lands as up and down once it is stood on end.
        .shadow(color: relief, radius: 0, x: Design.Stroke.hairline)
        .shadow(color: highlight, radius: 0, x: -Design.Stroke.hairline)
        // The foot keeps its margin, since the volume sits against the bottom edge of the spine. The
        // head gives most of its own back: what is there is a truncated title wanting the room.
        .padding(.leading, Design.Space.medium)
        .padding(.trailing, Design.Space.nudge)
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

/// The light falling across a spine: both edges turn away from it, the middle catches it, and the
/// very edge of the board is dark.
///
/// Its own view because a volume the reader doesn't hold is shaded like the books it stands between.
/// A gap in a run reads as a gap in a shelf rather than as a hole in the card.
struct SpineCurve: View {
    @Environment(\.colorScheme)
    private var scheme

    /// How dark the very edge goes, and the shading just inside it.
    ///
    /// The two scale together, and the edge is always the darker of them: light the edge alone and the
    /// darkest part of a spine ends up a twentieth of the way in, which is a ridge rather than a
    /// rounded board and reads as flat. Lighter on a light shelf, where an edge as black as the dark
    /// shelf's cuts the spine out of the page.
    private var edge: Color { .black.opacity(scheme == .dark ? 0.85 : 0.3) }

    private var shade: Color { .black.opacity(scheme == .dark ? 0.38 : 0.12) }

    /// The light caught along the middle of the board, and what the writing sits on.
    ///
    /// A dark title down the middle of a coloured spine has only the colour to stand against, and a
    /// cover's own colour is not chosen for the purpose. A white band there is both at once: the light
    /// a rounded board catches, and the paper a dark line needs under it.
    private var sheen: Color { .white.opacity(scheme == .dark ? 0.13 : 0.32) }

    /// Where the lit middle of the board begins and ends.
    ///
    /// Wider on a light shelf, where that band is also the paper the writing sits on: a narrow one
    /// leaves the ends of a long title out on the cover's own colour.
    private var litBand: (from: CGFloat, to: CGFloat) { scheme == .dark ? (0.32, 0.66) : (0.22, 0.78) }

    /// Where the shading at each edge has faded out altogether.
    private var clearOf: (from: CGFloat, to: CGFloat) { scheme == .dark ? (0.14, 0.86) : (0.1, 0.9) }

    var body: some View {
        LinearGradient(
            stops: [
                // The very edge of a spine turns away from the light altogether. A hard line rather
                // than a fade, and thin: it is the last two hundredths of the width on either side.
                .init(color: edge, location: 0),
                .init(color: edge, location: 0.02),
                .init(color: shade, location: 0.05),
                .init(color: .clear, location: clearOf.from),
                .init(color: sheen, location: litBand.from),
                .init(color: sheen, location: litBand.to),
                .init(color: .clear, location: clearOf.to),
                .init(color: shade, location: 0.95),
                .init(color: edge, location: 0.98),
                .init(color: edge, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

/// The volume, on a little plate at the foot of a spine, the way a numbered set carries its number:
/// set into the binding rather than printed along with the title.
struct SpinePlate: View {
    let number: Int

    @Environment(\.colorScheme)
    private var scheme

    var body: some View {
        Text(number, format: .number)
            .font(Design.Style.spine.monospacedDigit())
            .padding(.horizontal, Design.Space.extraSmall)
            .padding(.vertical, Design.Space.nudge)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.spine)
                    .fill(scheme == .dark ? .black.opacity(0.38) : .white.opacity(0.28))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.spine)
                    .strokeBorder(.black.opacity(0.3), lineWidth: Design.Stroke.hairline)
            )
    }
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
                .opacity(Self.faded)

            // Half the light the books beside it catch, and its own alpha rather than the slot's: a
            // fade laid over the whole thing took the shading down to a quarter and flattened it.
            SpineCurve()
                .opacity(Self.faded)

            RoundedRectangle(cornerRadius: Design.Radius.spine)
                .strokeBorder(Design.Surface.edge, lineWidth: Design.Stroke.hairline)
                .opacity(Self.faded)

            // Set the way a book that is here carries its own volume: on its plate at the foot of the
            // spine, so a gap in a run reads as one of the run rather than as a note beside it.
            if width > Design.Size.spine {
                SpinePlate(number: number)
                    .opacity(Self.faded)
            } else {
                HStack(spacing: 0) {
                    SpinePlate(number: number)

                    Spacer(minLength: 0)
                }
                .padding(.leading, Design.Space.medium)
                .frame(width: height, height: width)
                .rotationEffect(.degrees(-90))
                .opacity(Self.faded)
            }
        }
        .frame(width: width, height: height)
        .clipShape(.rect(cornerRadius: Design.Radius.spine))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume \(number), not in your library")
    }

    /// How much of a book a gap is: half there, and half of everything it is made of.
    private static let faded: Double = 0.5
}
