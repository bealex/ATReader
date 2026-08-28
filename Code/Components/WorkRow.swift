//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import SwiftUI

/// A book as it appears in every list: cover, title, author and the reader's own position.
struct WorkRow: View {
    let work: WorkSummary
    var showsProgress = true
    /// Off where the list already groups by series, so the row doesn't repeat its own heading.
    var showsSeries = true
    /// Chapters published since the last daily sweep, surfaced as a badge on the cover.
    var newChapters = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverImage(
                url: work.coverURL,
                width: 64,
                progress: showsProgress ? work.readingProgress : nil,
                isLocal: LocalBooks.isLocal(work.id)
            )
                .overlay(alignment: .topTrailing) {
                    if newChapters > 0 {
                        Text(newChapters, format: .number)
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red, in: .capsule)
                            .offset(x: 6, y: -6)
                            .accessibilityHidden(true)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(work.title)
                    .font(.headline)
                    .lineLimit(2)

                Text(work.authorLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if showsSeries, let series = work.seriesTitle, !series.isEmpty {
                    Text(series)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                WorkBadges(work: work, showsProgress: showsProgress)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [ work.title, work.authorLine ]

        if newChapters > 0 {
            parts.append(String(localized: "\(newChapters) new chapters"))
        }

        if showsProgress, let percent = WorkFormatting.progress(work.readingProgress) {
            parts.append(String(localized: "\(percent) read"))
        }

        parts.append(
            work.isOngoing
                ? String(localized: "still being written")
                : String(localized: "complete")
        )
        return parts.joined(separator: ", ")
    }
}
