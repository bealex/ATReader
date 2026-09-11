//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// A list row that opens another screen: its label, and the chevron that says so.
///
/// For a row that pushes through a button, since a `NavigationLink` only draws its chevron inside a
/// SwiftUI stack.
public struct DisclosureLabel<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: Design.Space.small) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.forward")
                .font(Design.Style.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
    }
}
