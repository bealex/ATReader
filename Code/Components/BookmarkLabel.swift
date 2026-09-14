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
    /// The words the mark stands on, which is what tells one mark from another. A mark written before
    /// marks kept any has none, and stands by its figure alone as it always did.
    let text: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.medium) {
            Image(systemName: "bookmark.fill")
                .font(Design.Style.caption)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            if let words {
                Text(words)
                    .font(Design.Style.item)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }

            if let written {
                Text(written)
                    .font(Design.Style.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.leading, Design.Space.section)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Bookmark"))
        .accessibilityValue([ words, written ].compactMap { $0 }.joined(separator: ", "))
    }

    private var written: String? {
        share?.formatted(.percent.precision(.fractionLength(0)))
    }

    /// The marked words on one run, since the stretch crosses paragraphs and a list row is a line or
    /// two. Whatever stood between them is gone with them.
    private var words: String? {
        text?.split(whereSeparator: \.isWhitespace).joined(separator: " ").nilWhenBlank
    }
}

private extension String {
    var nilWhenBlank: String? { isEmpty ? nil : self }
}
