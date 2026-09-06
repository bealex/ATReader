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
public struct ChapterPageView: UIViewRepresentable {
    public let layout: ChapterLayout
    public let pageIndex: Int

    public init(layout: ChapterLayout, pageIndex: Int) {
        self.layout = layout
        self.pageIndex = pageIndex
    }

    public func makeUIView(context: Context) -> PageView {
        let view = PageView()
        view.backgroundColor = .clear
        view.isOpaque = false
        return view
    }

    public func updateUIView(_ view: PageView, context: Context) {
        view.apply(layout: layout, pageIndex: pageIndex)
    }

    public final class PageView: UIView {
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

        override public func layoutSubviews() {
            super.layoutSubviews()
            setNeedsDisplay()
        }

        override public func draw(_ rect: CGRect) {
            layout?.draw(page: pageIndex)
        }
    }
}
