//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

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
    /// Centres a boxed label, a plate or a pill, on the capitals of the text style beside it.
    ///
    /// A box is much smaller than the words it stands with, so sitting it on the baseline stands it
    /// above the letters, and hanging it from the baseline drops it below them. Its middle goes on the
    /// middle of their capitals, which is where the eye reads a line.
    public func centredOnCapitals(of style: Font.TextStyle) -> some View {
        modifier(CapitalCentring(style: style))
    }
}

private struct CapitalCentring: ViewModifier {
    let style: Font.TextStyle

    @Environment(\.dynamicTypeSize)
    private var typeSize

    func body(content: Content) -> some View {
        content.alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + capHeight / 2 }
    }

    /// How tall the capitals of the style stand, at the reader's type size.
    private var capHeight: CGFloat {
        #if canImport(UIKit)
            let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))

            return UIFont.preferredFont(forTextStyle: Self.uiStyle(style), compatibleWith: traits).capHeight
        #else
            return 0
        #endif
    }

    #if canImport(UIKit)
        private static func uiStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
            switch style {
                case .largeTitle: .largeTitle
                case .title: .title1
                case .title2: .title2
                case .title3: .title3
                case .headline: .headline
                case .subheadline: .subheadline
                case .callout: .callout
                case .footnote: .footnote
                case .caption: .caption1
                case .caption2: .caption2
                default: .body
            }
        }
    #endif
}
