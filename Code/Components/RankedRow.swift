//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import DesignSystem
import SwiftUI

/// A top-list row: the position, then the usual book row.
struct RankedRow: View {
    let rank: Int
    let work: Book

    var body: some View {
        HStack(alignment: .top, spacing: Design.Space.medium) {
            Text("\(rank)")
                .font(Design.Style.title.monospacedDigit())
                .foregroundStyle(rank <= 3 ? Design.Palette.accent : Design.Palette.neutral)
                .frame(minWidth: Design.Size.mark, alignment: .trailing)
                .accessibilityHidden(true)

            BookRow(work: work, showsProgress: false)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(rank). \(work.title), \(work.authorLine)")
    }
}
