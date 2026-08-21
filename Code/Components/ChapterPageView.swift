//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import CoreText
import SwiftUI
import UIKit

/// Draws one page of a chapter.
///
/// This is CoreText rather than `Text` for two reasons: SwiftUI has no justified alignment, and drawing
/// through the same framesetter that produced the page breaks guarantees the page shows exactly what
/// pagination measured.
struct ChapterPageView: UIViewRepresentable {
    let layout: ChapterLayout
    let pageIndex: Int

    func makeUIView(context: Context) -> PageView {
        let view = PageView()
        view.backgroundColor = .clear
        view.isOpaque = false
        return view
    }

    func updateUIView(_ view: PageView, context: Context) {
        view.apply(layout: layout, pageIndex: pageIndex)
    }

    /// The drawing surface. It holds a laid-out chapter rather than raw text, so a page turn draws an
    /// already typeset frame instead of building one.
    final class PageView: UIView {
        private var layout: ChapterLayout?
        private var pageIndex = -1

        func apply(layout: ChapterLayout, pageIndex: Int) {
            guard layout !== self.layout || pageIndex != self.pageIndex else { return }

            self.layout = layout
            self.pageIndex = pageIndex
            isAccessibilityElement = true
            accessibilityTraits = .staticText
            accessibilityIdentifier = "reader.pageText"
            accessibilityLabel = layout.pageText(pageIndex)
            setNeedsDisplay()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            setNeedsDisplay()
        }

        override func draw(_ rect: CGRect) {
            guard
                let context = UIGraphicsGetCurrentContext(),
                let frame = layout?.frame(forPage: pageIndex)
            else {
                return
            }

            // CoreText draws bottom-up; flip into UIKit's coordinate space.
            context.textMatrix = .identity
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            CTFrameDraw(frame, context)
        }
    }
}
