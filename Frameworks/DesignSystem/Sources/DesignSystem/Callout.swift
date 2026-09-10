//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// A short aside, shown beside the thing it belongs to: a note, a gloss, a definition.
///
/// Wide enough to read a sentence across and no wider, and it scrolls once it outgrows its depth, so a
/// long aside stays an aside instead of becoming a screen.
///
/// What names the aside stands apart from what it says, above a rule: a note opening with the same
/// figure that called it up reads as though the figure were the first word of the note.
///
/// The colours are given rather than read off `Design`. The one caller so far is the reader's page,
/// whose colours belong to whoever is reading.
public struct Callout<Content: View>: View {
    /// What called the aside up: a note's own figure, where it has one.
    public let title: String?
    public var foreground: Color = .primary
    public var background: Color = Design.Surface.card
    /// How the aside is put away, where whoever showed it offers a button for that.
    public var onClose: (() -> Void)?

    private let content: Content

    public init(
        title: String? = nil,
        foreground: Color = .primary,
        background: Color = Design.Surface.card,
        onClose: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.foreground = foreground
        self.background = background
        self.onClose = onClose
        self.content = content()
    }

    /// The ground an aside stands on, which the shape around it has to be given as well.
    ///
    /// The colour behind it, carried towards the colour on it: lighter than a dark page, darker than a
    /// light one, without either being a colour of its own. An aside has to be told from what it
    /// covers at a glance, so this is the full veil rather than a hint of one.
    public static func surface(over background: Color, with foreground: Color) -> Color {
        background.mix(with: foreground, by: Design.Palette.veil)
    }

    private var surface: Color { Self.surface(over: background, with: foreground) }

    /// What names the aside, and the way out of it.
    private var header: some View {
        HStack(spacing: Design.Space.medium) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(Design.Style.caption.monospacedDigit())
                    .foregroundStyle(foreground.opacity(0.55))
            }

            Spacer(minLength: 0)

            if let onClose { closeButton(onClose) }
        }
    }

    /// Drawn from the aside's own two colours rather than from a material, which would follow the
    /// system's light or dark instead of the ground this is standing on.
    private func closeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: Design.Size.glyph(in: Design.Size.mark), weight: .semibold))
                .foregroundStyle(foreground.opacity(0.55))
                .frame(width: Design.Size.mark, height: Design.Size.mark)
                .background(foreground.opacity(Design.Palette.veil), in: .circle)
                // A mark this small is not a target, so the reach around it is the one a finger needs.
                .frame(width: Design.Size.control, height: Design.Size.control)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("callout.close")
        .accessibilityLabel(Text("Close", bundle: .module))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.medium) {
                if title?.isEmpty == false || onClose != nil {
                    header

                    Divider().overlay(foreground.opacity(Design.Palette.veil))
                }

                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Design.Space.extraLarge)
            .padding(.top, Design.Space.large)
            .padding(.bottom, Design.Space.extraLarge)
        }
        .scrollBounceBehavior(.basedOnSize)
        // A width it is set to rather than one it may take: a popover asks its content how large it is,
        // and content that would fit anything is given the least it can be shown in.
        .frame(width: Design.Size.callout)
        .frame(maxHeight: Design.Size.calloutDepth)
        // Lifted off whatever it covers: an aside the same colour as the page behind it reads as a
        // hole in that page rather than as something standing over it. Rounded to the same corner the
        // shape behind it carries, so a card standing on that shape doesn't square off its corners.
        .background(surface, in: .rect(cornerRadius: Design.Radius.medium))
        // Contained rather than combined: combining swallows the close button, which leaves the one
        // way out of an aside unreachable by touch.
        .accessibilityElement(children: .contain)
    }
}

public extension Callout where Content == CalloutText {
    /// An aside that is only words, set in the app's own type.
    init(
        title: String? = nil,
        text: String,
        foreground: Color = .primary,
        background: Color = Design.Surface.card,
        onClose: (() -> Void)? = nil
    ) {
        self.init(title: title, foreground: foreground, background: background, onClose: onClose) {
            CalloutText(text: text)
        }
    }
}

/// The words of an aside that carries nothing but words.
public struct CalloutText: View {
    public let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(Design.Style.item)
            // Without this the popover measures one line and clips the rest of the aside.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Where an aside stands, given the point it is hung on and the room it has to stand in.
///
/// Arithmetic rather than a view, so it can be checked without a screen. What it decides is which side
/// of the point the card takes, and how far the card has to give way to stay on screen.
public struct CalloutPlacement: Equatable, Sendable {
    /// The card's own middle, measured across the container.
    public let across: CGFloat
    /// Where the pointer's tip lands, down the container.
    public let along: CGFloat
    /// True where the card stands above what it points at, its pointer running down to it.
    public let pointsDown: Bool

    public init(across: CGFloat, along: CGFloat, pointsDown: Bool) {
        self.across = across
        self.along = along
        self.pointsDown = pointsDown
    }

    /// Everything a run of boxes covers, as the one thing an aside stands clear of.
    ///
    /// Words picked across several lines are several boxes and one thing, and an aside clearing only
    /// the first of them would stand over the rest.
    public static func bounds(around rects: [CGRect]) -> CGRect? {
        guard let first = rects.first else { return nil }

        return rects.dropFirst().reduce(first) { $0.union($1) }
    }

    /// A card takes whichever side of the thing has more room, and slides along until it fits.
    ///
    /// It points at the near edge of what it belongs to rather than at the middle of it, so it never
    /// stands over the very thing it was opened for: the top edge when above, the bottom when below.
    public static func make(over rect: CGRect, in container: CGSize, width: CGFloat, margin: CGFloat) -> Self {
        let half = width / 2
        let pointsDown = rect.midY > container.height / 2
        let along = pointsDown ? rect.minY : rect.maxY

        // Nowhere to slide to: a card wider than the room it has is centred and stands where it is.
        guard
            container.width > width + margin * 2
        else {
            return Self(across: container.width / 2, along: along, pointsDown: pointsDown)
        }

        return Self(
            across: min(max(rect.midX, half + margin), container.width - half - margin),
            along: along,
            pointsDown: pointsDown
        )
    }
}

/// A card with a pointer, drawn as one path so the two cannot be two colours.
///
/// The system's own popover draws its arrow as part of the presentation rather than of the content, and
/// hands over neither: a ground given to the content stops at the card's edge, and `presentationBackground`
/// does not reach the arrow. Measured, not guessed — see `CalloutBackgroundUITests`.
public struct CalloutShape: Shape {
    /// Where the pointer meets the card, across the shape.
    public var pointerX: CGFloat
    /// True where the card stands above what it points at.
    public var pointsDown: Bool

    public static let pointer = CGSize(width: Design.Space.extraLarge, height: Design.Space.medium)

    public init(pointerX: CGFloat, pointsDown: Bool) {
        self.pointerX = pointerX
        self.pointsDown = pointsDown
    }

    public func path(in rect: CGRect) -> Path {
        let card = CGRect(
            x: rect.minX,
            y: pointsDown ? rect.minY : rect.minY + Self.pointer.height,
            width: rect.width,
            height: rect.height - Self.pointer.height
        )
        let radius = Design.Radius.medium
        var path = Path(roundedRect: card, cornerRadius: radius)

        // Kept clear of the corners, so the pointer always leaves the card's straight edge.
        let half = Self.pointer.width / 2
        let base = pointsDown ? card.maxY : card.minY
        let apex = pointsDown ? rect.maxY : rect.minY
        let along = min(max(pointerX, card.minX + radius + half), card.maxX - radius - half)

        path.move(to: CGPoint(x: along - half, y: base))
        path.addLine(to: CGPoint(x: along, y: apex))
        path.addLine(to: CGPoint(x: along + half, y: base))
        path.closeSubpath()
        return path
    }
}

/// How an aside comes and goes.
///
/// Out of the thing it belongs to and back into it, so it reads as that thing opening rather than as a
/// card arriving from nowhere. A little bounce on the way out and none on the way back: a bounce says
/// something has arrived, and nothing is arriving when one is put away.
public enum CalloutMotion {
    // The bounce is asked for rather than left at the default, which measured as no overshoot at all.
    public static var showing: Animation { .bouncy(duration: showingSeconds, extraBounce: 0.15) }
    public static var hiding: Animation { .smooth(duration: hidingSeconds) }

    public static var showingSeconds: Double { 0.24 * MotionScale.factor }
    public static var hidingSeconds: Double { 0.18 * MotionScale.factor }
}

/// Holds an aside on screen for as long as it is coming or going, and drives both with a number.
///
/// The aside used to be inserted and removed, with a transition to animate each. A transition only runs
/// where SwiftUI counts the insertion as animatable, and in the reader's tree it did not: the aside
/// arrived fully formed however the change was wrapped. Owning the value removes the question.
private struct CalloutPresenter<Item: Identifiable, Content: View>: View {
    let rect: CGRect
    let ground: Color
    let coversSafeArea: Bool
    @Binding
    var item: Item?
    @ViewBuilder
    let content: (Item) -> Content

    /// What is on screen, which outlives `item` by however long it takes to go away.
    @State
    private var held: Item?

    /// And what it was hung over, kept for the same reason: the caller lets go of that the moment the
    /// aside is dismissed, and an aside shrinking towards a place nothing is any more goes to the
    /// corner of the screen instead of back into the words it came out of.
    @State
    private var heldRect: CGRect = .zero

    @State
    private var reach: CGFloat = 0

    var body: some View {
        ZStack {
            if let held {
                CalloutOverlay(
                    rect: heldRect,
                    ground: ground,
                    coversSafeArea: coversSafeArea,
                    reach: reach,
                    dismiss: { item = nil },
                    content: { content(held) }
                )
            }
        }
        .onChange(of: item?.id, initial: true) { _, _ in follow() }
        // A thing that moves while its aside is open takes the aside with it.
        .onChange(of: rect) { _, moved in
            guard item != nil else { return }

            heldRect = moved
        }
    }

    private func follow() {
        guard
            let item
        else {
            guard held != nil else { return }

            withAnimation(CalloutMotion.hiding) { reach = 0 }

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(CalloutMotion.hidingSeconds))

                if self.item == nil { held = nil }
            }
            return
        }

        held = item
        heldRect = rect
        reach = 0

        // A tick later, so the aside is on screen at nothing before it is asked to grow. Animating a
        // value the same view was inserted with animates nothing.
        Task { @MainActor in
            withAnimation(CalloutMotion.showing) { reach = 1 }
        }
    }
}

/// An aside standing over the view it belongs to, pointing at the thing that called it up.
///
/// Drawn here rather than presented as a popover, because a popover keeps its own container and its
/// own arrow, and clamps a card this wide to the middle of the screen wherever it was hung.
struct CalloutOverlay<Content: View>: View {
    /// What the aside belongs to, which it points at and never stands over.
    let rect: CGRect
    let ground: Color
    /// True where the view this stands over reaches past the safe area, as a reader's page does. The
    /// aside then counts from the same corner that view does, and the caller hands over the places
    /// it already has rather than correcting each one.
    let coversSafeArea: Bool
    /// How far out the aside stands, from nothing to all of it. A number rather than a transition,
    /// because a transition only runs where SwiftUI treats the insertion as animatable, and in a tree
    /// that rebuilds as often as a reader's page does it silently did not.
    let reach: CGFloat
    let dismiss: () -> Void
    @ViewBuilder
    let content: Content

    var body: some View {
        GeometryReader { geometry in
            let placement = CalloutPlacement.make(
                over: rect,
                in: geometry.size,
                width: Design.Size.callout,
                margin: Design.Space.large
            )

            ZStack {
                // A layer to tap away on. Anything less than a colour takes no touches at all.
                Color.black
                    .opacity(0.001)
                    .contentShape(.rect)
                    .onTapGesture(perform: dismiss)
                    .accessibilityIdentifier("callout.scrim")
                    .accessibilityLabel(Text("Close", bundle: .module))
                    .opacity(reach)

                placed(placement, in: geometry.size)
            }
            .ignoresSafeArea(.container, edges: coversSafeArea ? .all : [])
        }
        .ignoresSafeArea(.container, edges: coversSafeArea ? .all : [])
    }

    /// The card, stood where it belongs by what it is given rather than by what it measures.
    ///
    /// Aligned into a region carved out with padding, so nothing has to know how tall the card came
    /// out. Measuring it first meant hiding it until the measurement arrived, and a card hidden for
    /// its first frames plays its whole arrival where nobody can see it.
    private func placed(_ placement: CalloutPlacement, in size: CGSize) -> some View {
        card(pointsDown: placement.pointsDown, across: placement.across)
            .frame(width: Design.Size.callout)
            // Grown out of the thing it points at, and shrunk back into it. On the card itself: an
            // anchor is a fraction of whatever it is applied to, and on the region below it named a
            // corner of the whole page rather than the tip of the pointer.
            .scaleEffect(0.1 + 0.9 * reach, anchor: growth(from: placement))
            .opacity(reach)
            .padding(.leading, max(0, placement.across - Design.Size.callout / 2))
            .frame(maxWidth: .infinity, alignment: .leading)
            // The region stops at the edge the pointer stands on, and the card is held against it.
            .padding(.bottom, placement.pointsDown ? max(0, size.height - placement.along) : 0)
            .padding(.top, placement.pointsDown ? 0 : max(0, placement.along))
            .frame(maxHeight: .infinity, alignment: placement.pointsDown ? .bottom : .top)
    }

    /// The corner of the card its pointer stands at, which is what it grows out of and shrinks back
    /// into. Kept inside the card, so a pointer pushed towards an edge still grows from its own tip.
    private func growth(from placement: CalloutPlacement) -> UnitPoint {
        let width = Design.Size.callout
        let along = (rect.midX - (placement.across - width / 2)) / width

        return UnitPoint(x: min(max(along, 0), 1), y: placement.pointsDown ? 1 : 0)
    }

    private func card(pointsDown: Bool, across: CGFloat) -> some View {
        content
            .padding(pointsDown ? .bottom : .top, CalloutShape.pointer.height)
            .background(
                CalloutShape(pointerX: rect.midX - across + Design.Size.callout / 2, pointsDown: pointsDown)
                    .fill(ground)
                    // Cast by the card and its pointer together, since a shadow follows the shape it
                    // is drawn from. Black whatever the page is: a shadow is an absence of light.
                    .shade(.panel)
            )
    }
}

public extension View {
    /// Hangs an aside over something in this view's own space, pointing at it without covering it.
    ///
    /// Drawn into this view rather than presented, so the card and its pointer are one filled path in
    /// one colour, and so a wide card can stand where it was hung instead of being clamped to the
    /// middle of the screen. `ground` is what that path is filled with.
    ///
    /// `rect` is what the aside belongs to, in this view's own coordinates: a marker, a run of picked
    /// words. The aside takes the side of it with more room and points at its near edge, so what was
    /// asked about stays in sight.
    func callout<Item: Identifiable, Content: View>(
        over rect: CGRect,
        item: Binding<Item?>,
        ground: Color,
        coversSafeArea: Bool = false,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        overlay {
            CalloutPresenter(rect: rect, ground: ground, coversSafeArea: coversSafeArea, item: item) {
                content($0)
            }
        }
    }
}
