//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// A list section's header with an ⓘ at its far end, which opens a dialog explaining the section.
///
/// ```swift
/// Section { … } header: {
///     ExplainedHeader(Text("Backup"), explanation: Text("How a backup is written and put back."))
/// }
/// ```
public struct ExplainedHeader: View {
    private let title: Text
    private let explanation: Text

    @State
    private var isExplaining = false

    public init(_ title: Text, explanation: Text) {
        self.title = title
        self.explanation = explanation
    }

    public var body: some View {
        Button {
            isExplaining = true
        } label: {
            RowStack(spacing: Design.Space.small) {
                title

                Spacer(minLength: 0)

                LineGlyph(systemImage: "info.circle")
                    .fontWeight(.light)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(Text("Explains this section", bundle: .module))
        .alert(title, isPresented: $isExplaining, actions: {}, message: { explanation })
    }
}
