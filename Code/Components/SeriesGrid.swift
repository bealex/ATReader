//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import DesignSystem
import SwiftUI

/// How a series stands on its shelf.
enum Shelf {
    /// The gap between books. The same figure decides how many covers go in a row, so both readings
    /// of it come from here rather than from two places that have to be kept in step.
    static let gap = Design.Space.small
}

/// One place in a series: a book the reader holds, or a volume they don't.
enum SeriesSlot: Identifiable {
    case book(Book, number: Int?, title: String, isRead: Bool)
    case missing(Int)

    var id: String {
        switch self {
            case let .book(work, _, _, _): "book:\(work.id)"
            case let .missing(number): "gap:\(number)"
        }
    }
}

/// A series as its own shelf: covers for what is left to read, spines for what is behind the reader.
///
/// Two ways of standing rather than two lists. Every book is here in both, so a series never hides one
/// of its volumes; what changes is how much room a book the reader is done with takes up.
struct SeriesGrid<Actions: View>: View {
    let slots: [SeriesSlot]
    /// How wide a cover stands here, worked out once for the whole shelf so every card agrees.
    let coverWidth: CGFloat
    /// True while every book stands as a cover, false while the ones read stand as spines.
    let showsEveryCover: Bool
    let zoom: Namespace.ID
    /// Whether a book is picked out, while the shelf is picking books. Nothing while it isn't.
    let isPicked: ((Book) -> Bool)?
    let onToggle: () -> Void
    let onOpen: (Book) -> Void
    @ViewBuilder
    let actions: (Book) -> Actions

    @Environment(BookOrigins.self)
    private var origins

    /// Ties a book's spine to its own cover, so switching between the two ways of standing moves each
    /// book from where it was to where it is going rather than replacing one picture with another.
    @Namespace
    private var shelf

    private var height: CGFloat { Design.Size.coverHeight(width: coverWidth) }

    var body: some View {
        FlowLayout(spacing: Shelf.gap, lineSpacing: Shelf.gap) {
            ForEach(slots) { slot in
                switch slot {
                    case let .book(work, number, title, isRead):
                        if showsEveryCover || !isRead {
                            cover(work)
                        } else {
                            BookSpine(work: work, number: number, title: title, height: height, coverWidth: coverWidth)
                                .matchedGeometryEffect(id: work.id, in: shelf)
                                .contentShape(.rect)
                                .onTapGesture(perform: onToggle)
                                .transition(.opacity)
                        }
                    case let .missing(number):
                        MissingSlot(
                            number: number,
                            width: showsEveryCover ? coverWidth : Design.Size.spine,
                            height: height
                        )
                        .contentShape(.rect)
                        .onTapGesture(perform: onToggle)
                        .transition(.opacity)
                }
            }
        }
    }

    private func cover(_ work: Book) -> some View {
        CoverImage(
            url: work.coverURL,
            width: coverWidth,
            progress: work.readingProgress,
            height: height,
            origin: origins.origin(of: work.id),
            isOngoing: work.isOngoing
        )
        .matchedGeometryEffect(id: work.id, in: shelf)
        .overlay(alignment: .topTrailing) {
            if let isPicked {
                LineGlyph(systemImage: isPicked(work) ? "checkmark.circle.fill" : "circle")
                    .font(Design.Control.barGlyph)
                    .foregroundStyle(isPicked(work) ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .padding(Design.Space.extraSmall)
            }
        }
        .matchedTransitionSource(id: work.id, in: zoom)
        .contentShape(.rect)
        .onTapGesture { onOpen(work) }
        .contextMenu { actions(work) }
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(work.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the book")
    }
}
