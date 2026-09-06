//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// A spinner for a screen with nothing behind it yet.
///
/// It fills the screen and brings its own background. A spinner drawn straight onto whatever the screen
/// happens to be showing reads as something gone wrong rather than something being loaded.
struct LoadingOverlay: View {
    let title: LocalizedStringKey
    /// What VoiceOver reads. The title carries an ellipsis, which it would spell out.
    let label: LocalizedStringKey
    var background = Design.Surface.screen

    var body: some View {
        ProgressView(title)
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background)
            .accessibilityLabel(label)
    }
}

/// A spinner for a list that already has rows: it sits on a card over them rather than covering them,
/// since the rows underneath are still worth reading while the new ones arrive.
struct LoadingCard: View {
    let title: LocalizedStringKey
    let label: LocalizedStringKey

    var body: some View {
        ProgressView(title)
            .controlSize(.large)
            .padding(.horizontal, Design.Space.huge)
            .padding(.vertical, Design.Space.extraLarge)
            .background(.regularMaterial, in: .rect(cornerRadius: Design.Radius.large))
            .shade(.card)
            .accessibilityLabel(label)
    }
}
