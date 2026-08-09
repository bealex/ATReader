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
    /// Chapters published since the last daily sweep, surfaced as a badge on the cover.
    var newChapters = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverImage(url: work.coverURL, width: 64)
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

                if let series = work.seriesTitle, !series.isEmpty {
                    Text(series)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                metadata

                if showsProgress, let progress = work.readingProgress, progress > 0 {
                    progressBar(progress)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var metadata: some View {
        HStack(spacing: 10) {
            if let length = WorkFormatting.length(work.textLength) {
                Label(length, systemImage: "doc.text")
            }

            if let likes = WorkFormatting.likes(work.likeCount) {
                Label(likes, systemImage: "heart")
            }

            if work.isOngoing {
                Label("Ongoing", systemImage: "pencil")
            }

            if work.status == .sales || work.status == .subscription {
                Label("Paid", systemImage: "lock")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
    }

    private func progressBar(_ progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.accentColor)

            HStack(spacing: 6) {
                if let percent = WorkFormatting.progress(progress) {
                    Text("\(percent) read")
                }

                if let read = WorkFormatting.lastRead(work.lastReadTime) {
                    Text("· \(read)")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
        .accessibilityHidden(true)
    }

    private var accessibilityLabel: String {
        var parts = [ work.title, work.authorLine ]

        if newChapters > 0 {
            parts.append(String(localized: "\(newChapters) new chapters"))
        }

        if let percent = WorkFormatting.progress(work.readingProgress) {
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
