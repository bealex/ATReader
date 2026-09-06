//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// A spinner for a screen with nothing behind it yet.
///
/// It fills the screen and brings its own background. A spinner drawn straight onto whatever the screen
/// happens to be showing reads as something gone wrong rather than something being loaded.
public struct LoadingOverlay: View {
    public let title: LocalizedStringKey
    /// What VoiceOver reads. The title carries an ellipsis, which it would spell out.
    public let label: LocalizedStringKey
    public var background: Color

    /// The keys are the caller's, so they resolve against the app's catalogue and not this package's.
    public init(title: LocalizedStringKey, label: LocalizedStringKey, background: Color = Design.Surface.screen) {
        self.title = title
        self.label = label
        self.background = background
    }

    public var body: some View {
        ProgressView(title)
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background)
            .accessibilityLabel(label)
    }
}

/// A spinner for a list that already has rows: it sits on a card over them rather than covering them,
/// since the rows underneath are still worth reading while the new ones arrive.
public struct LoadingCard: View {
    public let title: LocalizedStringKey
    public let label: LocalizedStringKey

    public init(title: LocalizedStringKey, label: LocalizedStringKey) {
        self.title = title
        self.label = label
    }

    public var body: some View {
        ProgressView(title)
            .controlSize(.large)
            .padding(.horizontal, Design.Space.huge)
            .padding(.vertical, Design.Space.extraLarge)
            .background(.regularMaterial, in: .rect(cornerRadius: Design.Radius.large))
            .shade(.card)
            .accessibilityLabel(label)
    }
}
