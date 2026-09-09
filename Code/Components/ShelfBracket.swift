//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import DesignSystem
import SwiftUI

/// The line under a run of books that says where a series starts and where it ends.
///
/// A run reads as a run only if something holds it together: an author's shelf carries several series
/// and the books themselves say nothing about where one gives way to the next. The line ticks upward at
/// the outer edge of the first book and of the last, and where a run carries on onto the next row it is
/// left open, so an unclosed end reads as "continues".
struct ShelfBracket: Shape {
    let opens: Bool
    let closes: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let line = rect.midY
        let tick = line - Design.Space.small

        path.move(to: CGPoint(x: rect.minX, y: line))
        path.addLine(to: CGPoint(x: rect.maxX, y: line))

        if opens {
            path.move(to: CGPoint(x: rect.minX, y: line))
            path.addLine(to: CGPoint(x: rect.minX, y: tick))
        }

        if closes {
            path.move(to: CGPoint(x: rect.maxX, y: line))
            path.addLine(to: CGPoint(x: rect.maxX, y: tick))
        }

        return path
    }
}

/// A series' bracket with its name set over the line.
struct ShelfBand: View {
    let title: String
    let width: CGFloat
    let opens: Bool
    let closes: Bool

    var body: some View {
        ShelfBracket(opens: opens, closes: closes)
            .stroke(.tertiary, lineWidth: Design.Stroke.hairline)
            .frame(width: width, height: Design.Space.large)
            // Laid over rather than beside: as a second thing in a stack, a name wider than its own
            // line made the stack that much wider and took the line with it.
            .overlay {
                // Full name, then initials, then nothing. A name is set in full only where the line
                // it belongs to has the room for it: one hanging out past the books it names points
                // at books that are not its own.
                ViewThatFits(in: .horizontal) {
                    name(title)
                    name(Self.initials(of: title))
                    // Nothing, drawn as something. An `EmptyView` is erased from a builder, which
                    // leaves two candidates and the last one set overflowing when neither fits.
                    Color.clear.frame(width: 0, height: 0)
                }
                .frame(width: width)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
    }

    private func name(_ text: String) -> some View {
        Text(text)
            .font(Design.Style.spine)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Design.Space.extraSmall)
            .background(Design.Surface.card)
    }

    /// A name the line has no room for, as the letters its words begin with.
    static func initials(of title: String) -> String {
        title
            .split { !$0.isLetter && !$0.isNumber }
            .compactMap(\.first)
            .map { "\($0)." }
            .joined()
    }
}
