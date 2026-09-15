//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import DesignSystem
import SwiftUI

extension ReaderScreen {
    /// Where each mark on a page stands: a ribbon in the gutter, against the line it begins on.
    ///
    /// Contoured in the page's own ink rather than filled, so it reads as a mark made in the margin of
    /// the book rather than as chrome laid over it. It shrinks with the margin it hangs in, and a page
    /// set with no margin at all keeps it at the page's edge rather than dropping it.
    struct GutterMarks: View {
        let marks: [Model.StandingMark]
        /// Where the text stops and where the page does: the ribbon hangs between the two.
        let textEdge: CGFloat
        let pageWidth: CGFloat
        let ink: Color

        var body: some View {
            let room = max(0, pageWidth - textEdge)
            let scale = min(1, max(Self.least, (room - Design.Space.extraSmall) / Design.Size.bookmark))
            let width = Design.Size.bookmark * scale

            ForEach(marks) { mark in
                BookmarkShape()
                    .stroke(ink, lineWidth: Design.Stroke.readingShade)
                    .frame(width: width, height: Design.Size.bookmarkHeight * scale)
                    .position(
                        x: min(max(textEdge + room / 2, width / 2), pageWidth - width / 2),
                        y: mark.top + mark.height / 2
                    )
            }
            .accessibilityHidden(true)
        }

        /// How small the ribbon may be squeezed before it stops shrinking with the margin.
        private static let least: CGFloat = 0.5
    }
}
