//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// Glyph buttons standing together under one pane of glass, the way a bar sets out its own.
///
/// One button is a circle, since a capsule as tall as it is wide is one. The buttons inside are left
/// as they were written: the row sizes them, sets their glyphs and dims whichever is held.
public struct GlassRow<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: Design.Space.large) {
            content
        }
        .buttonStyle(GlassControl())
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

/// A glyph in a square the size of a fingertip, dimmed while it is held.
private struct GlassControl: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: Design.Size.glyph(in: Design.Size.touch)))
            .frame(width: Design.Size.touch, height: Design.Size.touch)
            .opacity(configuration.isPressed ? Self.held : 1)
            .contentShape(.rect)
    }

    private static let held = 0.4
}
