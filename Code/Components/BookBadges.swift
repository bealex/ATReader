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

            if let likes = BookFormatting.likes(work.likeCount) {
                Pill(title: likes, systemImage: "heart.fill", label: likes)
            }

            if showsUpdated, let updated = BookFormatting.updated(work.lastUpdateTime) {
                Pill(title: updated, systemImage: "clock", label: updated)
            }
        }
    }

    /// Where the book stands, which is the first thing a row says about it. A book its author has
    /// finished says nothing here: that is the ordinary case, and a pill for it would sit on every row.
    /// Being caught up is the ring's business.
    @ViewBuilder
    private var state: some View {
        if showsProgress, work.isFinishedReading {
            let title = String(localized: "Finished")
            Pill(title: title, systemImage: "checkmark.circle.fill", tint: Design.Palette.positive, label: title)
        } else if work.isOngoing {
            let title = String(localized: "Ongoing")
            Pill(title: title, systemImage: "pencil", label: title)
        }
    }
}
