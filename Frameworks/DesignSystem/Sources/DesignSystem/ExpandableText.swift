//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// Text cut to a few lines, with a control to open it where there is more.
///
/// The control appears only when the text is actually longer than the limit, which takes measuring:
/// a hidden copy with no limit is laid out at the same width, and being taller than the visible one is
/// what says the visible one was cut.
public struct ExpandableText: View {
    public let text: String
    public var lineLimit: Int

    @State
    private var isExpanded = false
    @State
    private var fullHeight: CGFloat = 0
    @State
    private var clampedHeight: CGFloat = 0

    private var isCut: Bool { fullHeight > clampedHeight + 1 }

    public init(_ text: String, lineLimit: Int = 5) {
        self.text = text
        self.lineLimit = lineLimit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.small) {
            Text(text)
                .lineLimit(isExpanded ? nil : lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(
                    for: CGFloat.self,
                    of: { $0.size.height },
                    action: { height in
                        guard !isExpanded else { return }

                        clampedHeight = height
                    }
                )
                .background {
                    Text(text)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { fullHeight = $0 })
                }

            if isCut {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    Text(isExpanded ? "Show less" : "Show more", bundle: .module)
                }
                .font(Design.Style.caption)
                .accessibilityHint(
                    Text(isExpanded ? "Shortens the text" : "Shows the rest of the text", bundle: .module)
                )
            }
        }
    }
}
