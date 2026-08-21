//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import UIKit

/// Draws one page of a chapter.
///
/// The page holds a laid-out chapter rather than raw text, so a turn draws a page TextKit has already
/// measured, and a page can never show something pagination didn't.
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
            layout?.draw(page: pageIndex)
        }
    }
}
