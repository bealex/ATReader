//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import DesignSystem
import SwiftUI

/// One of an author's series, as the shelf needs it.
struct ShelfRun: Identifiable {
    let id: String
    let title: String
    let slots: [SeriesSlot]
}

/// One book's place on an author's shelf.
private struct ShelfPlace: Identifiable {
    let slot: SeriesSlot
    /// The series it stands in, where it stands in one.
    let series: String?
    let width: CGFloat
    let height: CGFloat

    var id: String { slot.id }
}

/// A stretch of one row holding books of a single series, or of none.
private struct ShelfSpan: Identifiable {
    let series: ShelfRun?
    let places: [ShelfPlace]
    let opens: Bool
    let closes: Bool

    var id: String { (series?.id ?? "alone") + "|" + (places.first?.id ?? "") }

    func width(spacing: CGFloat) -> CGFloat {
        places.map(\.width).reduce(0, +) + spacing * CGFloat(max(0, places.count - 1))
    }
}

/// An author's books: their series in runs, and after them whatever stands on its own.
///
/// A reader follows writers more than they follow series, so one card holds everything of one author's
/// and a line under each run says where a series begins and ends. The rows are broken here rather than
/// by a flow layout, because a bracket has to know which books landed on which row and how wide they
/// came out.
struct AuthorShelfView<Actions: View, RunActions: View>: View {
    let runs: [ShelfRun]
    let alone: [SeriesSlot]
    let coverWidth: CGFloat
    /// What the shelf has to lay books out in.
    let available: CGFloat
    /// True while every book stands as a cover, false while the ones read stand as spines.
    let showsEveryCover: Bool
    let zoom: Namespace.ID
    /// Whether a book is picked out, while the shelf is picking books. Nothing while it isn't.
    let isPicked: ((Book) -> Bool)?
    let onToggle: () -> Void
    let onOpen: (Book) -> Void
    @ViewBuilder
    let actions: (Book) -> Actions
    @ViewBuilder
    let runActions: (ShelfRun) -> RunActions

    @Environment(BookOrigins.self)
    private var origins

    /// Ties a book's spine to its own cover, so switching between the two ways of standing moves each
    /// book from where it was to where it is going rather than replacing one picture with another.
    @Namespace
    private var shelf

    /// The shape of a cover this shelf has only just seen, which nothing had written down yet.
    @State
    private var measured: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.medium) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: Design.Space.extraSmall) {
                    HStack(alignment: .bottom, spacing: Shelf.gutter) {
                        ForEach(row) { place in item(place) }

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: Shelf.gutter) {
                        ForEach(spans(of: row)) { span in band(span) }

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .onPreferenceChange(CoverShape.self) { shape in
            guard shape > measured else { return }

            measured = shape
        }
    }

    // MARK: - What stands where

    private var places: [ShelfPlace] {
        let held = runs.flatMap { series in series.slots.map { place($0, in: series.id) } }

        return held + alone.map { place($0, in: nil) }
    }

    private func place(_ slot: SeriesSlot, in series: String?) -> ShelfPlace {
        ShelfPlace(slot: slot, series: series, width: width(of: slot), height: height(of: slot))
    }

    /// The books of each row, broken where the next one would not fit.
    private var rows: [[ShelfPlace]] {
        var broken: [[ShelfPlace]] = []
        var row: [ShelfPlace] = []
        var taken: CGFloat = 0

        for place in places {
            let needed = row.isEmpty ? place.width : place.width + Shelf.gutter

            if taken + needed > available, !row.isEmpty {
                broken.append(row)
                row = []
                taken = 0
            }

            row.append(place)
            taken += row.count == 1 ? place.width : place.width + Shelf.gutter
        }

        if !row.isEmpty { broken.append(row) }

        return broken
    }

    /// One row's stretches: books of one series standing together, and the loose ones between them.
    private func spans(of row: [ShelfPlace]) -> [ShelfSpan] {
        var spans: [ShelfSpan] = []
        var gathered: [ShelfPlace] = []

        func close() {
            defer { gathered = [] }

            guard let first = gathered.first else { return }

            let series = first.series.flatMap { name in runs.first { $0.id == name } }

            spans.append(ShelfSpan(
                series: series,
                places: gathered,
                opens: series.map { $0.slots.first?.id == first.id } ?? false,
                closes: series.map { $0.slots.last?.id == gathered.last?.id } ?? false
            ))
        }

        for place in row {
            if place.series != gathered.first?.series { close() }

            gathered.append(place)
        }

        close()

        return spans
    }

    @ViewBuilder
    private func band(_ span: ShelfSpan) -> some View {
        if let series = span.series {
            ShelfBand(
                title: series.title,
                width: span.width(spacing: Shelf.gutter),
                opens: span.opens,
                closes: span.closes
            )
            .contentShape(.rect)
            .contextMenu { runActions(series) }
        } else {
            // A book belonging to no series has nothing to hold it, and keeps its width so the run
            // beside it still lines up with the books above.
            Color.clear
                .frame(width: span.width(spacing: Shelf.gutter), height: Design.Space.large)
        }
    }

    // MARK: - How big a book is

    private var tallest: CGFloat {
        let known = max(measured, remembered)

        return known > 0 ? known : Shelf.unknownShape
    }

    /// Read off the slots rather than off the places, because a place is measured against this: going
    /// through them to work out how tall a book stands asks the question with its own answer.
    private var remembered: CGFloat {
        (runs.flatMap(\.slots) + alone)
            .compactMap { slot in
                guard case let .book(work, _, _, _) = slot else { return nil }

                return work.coverURL.flatMap(CoverShapes.aspect(for:))
            }
            .max() ?? 0
    }

    private var slotHeight: CGFloat { Design.Size.coverHeight(width: coverWidth, ratio: tallest) }

    private func standsAsCover(_ slot: SeriesSlot) -> Bool {
        guard case let .book(_, _, _, isRead) = slot else { return showsEveryCover }

        return showsEveryCover || !isRead
    }

    private func width(of slot: SeriesSlot) -> CGFloat {
        guard
            case let .book(work, _, _, _) = slot
        else {
            return showsEveryCover ? coverWidth : Design.Size.spine
        }

        return standsAsCover(slot) ? coverWidth : BookSpine.width(of: work, cover: coverWidth)
    }

    private func height(of slot: SeriesSlot) -> CGFloat {
        guard case let .book(work, _, _, _) = slot, !standsAsCover(slot) else { return slotHeight }

        let shape = work.coverURL.flatMap(CoverShapes.aspect(for:)) ?? tallest

        return Design.Size.coverHeight(width: coverWidth, ratio: shape)
    }

    // MARK: - One book

    @ViewBuilder
    private func item(_ place: ShelfPlace) -> some View {
        switch place.slot {
            case let .book(work, number, title, _):
                if standsAsCover(place.slot) {
                    cover(work)
                } else {
                    BookSpine(work: work, number: number, title: title, height: place.height, coverWidth: coverWidth)
                        .frame(height: slotHeight, alignment: .bottom)
                        .matchedGeometryEffect(id: work.id, in: shelf)
                        .contentShape(.rect)
                        .onTapGesture(perform: onToggle)
                        .transition(.opacity)
                }
            case let .missing(number):
                MissingSlot(number: number, width: place.width, height: slotHeight)
                    .contentShape(.rect)
                    .onTapGesture(perform: onToggle)
                    .transition(.opacity)
        }
    }

    private func cover(_ work: Book) -> some View {
        CoverImage(
            url: work.coverURL,
            width: coverWidth,
            progress: work.readingProgress,
            origin: origins.origin(of: work.id),
            isOngoing: work.isOngoing
        )
        // Every book on a shelf stands on the same line, so a cover shorter than the tallest keeps
        // its feet on the shelf and leaves its room above.
        .frame(width: coverWidth, height: slotHeight, alignment: .bottom)
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
