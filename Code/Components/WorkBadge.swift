//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import DesignSystem
import SwiftUI

/// One fact about a book, as a tinted pill: a glyph and a short phrase.
struct WorkBadge: View {
    /// A badge with no title is its glyph alone.
    let title: String?
    let systemImage: String
    var tint: Color = Design.Palette.neutral

    var body: some View {
        HStack(spacing: Design.Space.extraSmall) {
            Image(systemName: systemImage)
                .font(Design.Style.micro)
                .imageScale(.small)

            if let title {
                Text(title)
                    .font(Design.Style.micro)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Design.Space.small)
        .padding(.vertical, Design.Space.extraSmall)
        .background(Design.Surface.ground(tint), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title ?? String(localized: "Costs money"))
    }
}

/// The pills a book carries. Which of them a screen shows differs, so each is asked for by name.
///
/// How far the reader has got is not among them: the ring on the cover says that already, and saying it
/// twice on one row reads as two different facts.
struct WorkBadges: View {
    let work: WorkSummary
    /// Whether the reader's own standing in the book counts, which decides between Finished and Ongoing.
    var showsProgress = false
    var showsUpdated = false
    /// Overrides what the row itself can work out, for a screen that knows better. The book page can
    /// see which chapters are closed; a list has only what the book says about itself.
    var costsMoney: Bool?

    var body: some View {
        FlowLayout {
            state

            if costsMoney ?? work.needsBuying {
                WorkBadge(title: nil, systemImage: "dollarsign", tint: Design.Palette.caution)
            }

            if let likes = WorkFormatting.likes(work.likeCount) {
                WorkBadge(title: likes, systemImage: "heart.fill")
            }

            if showsUpdated, let updated = WorkFormatting.updated(work.lastUpdateTime) {
                WorkBadge(title: updated, systemImage: "clock")
            }
        }
    }

    /// Where the book stands, which is the first thing a row says about it. A book its author has
    /// finished says nothing here: that is the ordinary case, and a pill for it would sit on every row.
    /// Being caught up is the ring's business.
    @ViewBuilder
    private var state: some View {
        if showsProgress, work.isFinishedReading {
            WorkBadge(
                title: String(localized: "Finished"),
                systemImage: "checkmark.circle.fill",
                tint: Design.Palette.positive
            )
        } else if work.isOngoing {
            WorkBadge(title: String(localized: "Ongoing"), systemImage: "pencil")
        }
    }
}
