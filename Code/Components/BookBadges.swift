//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import DesignSystem
import SwiftUI

/// The pills a book carries. Which of them a screen shows differs, so each is asked for by name.
///
/// How far the reader has got is not among them: the ring on the cover says that already, and saying it
/// twice on one row reads as two different facts.
struct BookBadges: View {
    @Environment(ShelfSettings.self)
    private var settings

    let work: Book
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
                Pill(
                    title: nil,
                    systemImage: "dollarsign",
                    tint: Design.Palette.caution,
                    label: String(localized: "Costs money")
                )
            }

            if settings.showsLikes, let likes = BookFormatting.likes(work.likeCount) {
                Pill(title: likes, systemImage: "heart.fill", label: likes)
            }

            if showsUpdated, let updated = BookFormatting.updated(work.lastUpdateTime) {
                Pill(title: updated, systemImage: "clock", label: updated)
            }
        }
    }

    /// Where the reader stands in the book. A book its author has finished says nothing here: that is
    /// the ordinary case, and a pill for it would sit on every row. Being caught up is the ring's
    /// business, and one still being written is marked on its own cover.
    @ViewBuilder
    private var state: some View {
        if showsProgress, work.isFinishedReading {
            let title = String(localized: "Finished")
            Pill(title: title, systemImage: "checkmark.circle.fill", tint: Design.Palette.positive, label: title)
        }
    }
}
