//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import SwiftUI

/// One fact about a book, as a tinted pill: a glyph and a short phrase.
struct WorkBadge: View {
    let title: String
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.caption2)
                .imageScale(.small)

            Text(title)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.14), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

/// The pills a book carries. Which of them a screen shows differs, so each is asked for by name.
struct WorkBadges: View {
    let work: WorkSummary
    var showsLength = false
    var showsProgress = false
    var showsUpdated = false

    var body: some View {
        FlowLayout {
            if showsLength, let length = WorkFormatting.length(work.textLength) {
                WorkBadge(title: length, systemImage: "doc.text")
            }

            if let likes = WorkFormatting.likes(work.likeCount) {
                WorkBadge(title: likes, systemImage: "heart.fill", tint: .pink)
            }

            state

            if work.isPaid {
                WorkBadge(title: String(localized: "Paid"), systemImage: "lock.fill", tint: .indigo)
            }

            if showsProgress, !work.isReadToTheEnd, let percent = WorkFormatting.progress(work.readingProgress) {
                WorkBadge(title: String(localized: "\(percent) read"), systemImage: "book.fill", tint: .accentColor)
            }

            if showsUpdated, let updated = WorkFormatting.updated(work.lastUpdateTime) {
                WorkBadge(title: updated, systemImage: "clock")
            }
        }
    }

    /// Where the book stands: written to its end and read to its end is finished, and nothing else is.
    /// A book read as far as it goes while its author writes on says so instead.
    @ViewBuilder
    private var state: some View {
        if showsProgress, work.isFinishedReading {
            WorkBadge(title: String(localized: "Finished"), systemImage: "checkmark.circle.fill", tint: .green)
        } else {
            WorkBadge(
                title: work.isOngoing ? String(localized: "Ongoing") : String(localized: "Complete"),
                systemImage: work.isOngoing ? "pencil" : "checkmark.seal",
                tint: work.isOngoing ? .orange : .green
            )

            if showsProgress, work.isCaughtUp {
                WorkBadge(title: String(localized: "Caught up"), systemImage: "hourglass", tint: .teal)
            }
        }
    }
}
