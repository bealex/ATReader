//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// Lays its subviews out left to right and wraps to a new line when the width runs out.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = lines(of: subviews, within: width)
        let height = lines.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, lines.count - 1))

        return CGSize(width: min(width, lines.map(\.width).max() ?? 0), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var y = bounds.minY

        for line in lines(of: subviews, within: bounds.width) {
            var x = bounds.minX

            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                let origin = CGPoint(x: x, y: y + (line.height - size.height) / 2)
                subviews[index].place(at: origin, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }

            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(of subviews: Subviews, within width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var line = Line()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extended = line.indices.isEmpty ? size.width : line.width + spacing + size.width

            if !line.indices.isEmpty, extended > width {
                lines.append(line)
                line = Line(indices: [ index ], width: size.width, height: size.height)
                continue
            }

            line.indices.append(index)
            line.width = extended
            line.height = max(line.height, size.height)
        }

        if !line.indices.isEmpty { lines.append(line) }

        return lines
    }
}
