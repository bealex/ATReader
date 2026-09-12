//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import DesignSystem
import SwiftUI

/// A mark set out under the chapter it stands in, and how far into that chapter it is.
///
/// Indented rather than badged, because the row above it is what it belongs to: a list of chapters
/// with marks under them reads as one list, and a mark standing level with a chapter reads as another
/// chapter.
struct BookmarkLabel: View {
    /// How far into the chapter the mark stands, `0…1`, or nothing where the length is unknown.
    let share: Double?

    var body: some View {
        HStack(spacing: Design.Space.medium) {
            Image(systemName: "bookmark.fill")
                .font(Design.Style.caption)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            if let written {
                Text(written)
                    .font(Design.Style.item)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, Design.Space.section)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Bookmark"))
        .accessibilityValue(written ?? "")
    }

    private var written: String? {
        share?.formatted(.percent.precision(.fractionLength(0)))
    }
}
