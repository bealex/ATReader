//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// Items set side by side on one line.
///
/// Everything in a row sits on the same baseline, which is what makes a badge, a glyph and a title read
/// as one line rather than three things that happen to stand next to each other. Anything wanting a
/// different alignment is a stack rather than a row, and says so by being one.
public struct RowStack<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = Design.Space.small, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: spacing) { content }
    }
}

extension View {
    /// Sits a boxed label on the line rather than under it.
    ///
    /// A badge or a pill is text inside a padded ground, and a baseline drawn through its text hangs
    /// the ground below the line by whatever padding sits under it. Taking that padding out of the
    /// baseline the row is offered puts the box itself on the line, which is where the eye reads it.
    public func sitsOnTheLine() -> some View {
        // The whole of it, which is what puts the bottom of the ground on the line. Lifting the label's
        // own baseline by the padding leaves the box hanging by its descender, since a baseline carries
        // the descender below it and a box carries nothing.
        alignmentGuide(.firstTextBaseline) { $0.height }
    }
}
