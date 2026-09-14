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
    /// Which way the buttons run. A screen that keeps the device's own band down one side wants its
    /// controls down that side too, and a row of them turned on its end is still one pane of glass.
    public enum Axis: Sendable {
        case across
        case down
    }

    private let axis: Axis
    private let content: Content

    public init(_ axis: Axis = .across, @ViewBuilder content: () -> Content) {
        self.axis = axis
        self.content = content()
    }

    public var body: some View {
        stack
            .buttonStyle(GlassControl())
            .glassEffect(.regular.interactive(), in: .capsule)
    }

    @ViewBuilder
    private var stack: some View {
        switch axis {
            case .across: HStack(spacing: Design.Space.large) { content }
            case .down: VStack(spacing: Design.Space.large) { content }
        }
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
