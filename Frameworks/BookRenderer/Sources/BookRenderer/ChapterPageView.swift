//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import UIKit

/// Draws one chapter's share of a page.
///
/// The page holds lines the chapter has already composed and cut, so a turn draws what was measured
/// and a page can never show something the cutting didn't.
public struct ChapterPageView: UIViewRepresentable {
    public let layout: ChapterLayout
    public let page: ChapterLayout.Page

    public init(layout: ChapterLayout, page: ChapterLayout.Page) {
        self.layout = layout
        self.page = page
    }

    public func makeUIView(context: Context) -> PageView {
        let view = PageView()
        view.backgroundColor = .clear
        view.isOpaque = false
        return view
    }

    public func updateUIView(_ view: PageView, context: Context) {
        view.apply(layout: layout, page: page)
    }

    public final class PageView: UIView {
        private var layout: ChapterLayout?
        private var page: ChapterLayout.Page?

        func apply(layout: ChapterLayout, page: ChapterLayout.Page) {
            guard layout !== self.layout || page != self.page else { return }

            self.layout = layout
            self.page = page
            isAccessibilityElement = true
            accessibilityTraits = .staticText
            accessibilityIdentifier = "reader.pageText"
            accessibilityLabel = layout.pageText(page)
            setNeedsDisplay()
        }

        override public func layoutSubviews() {
            super.layoutSubviews()
            setNeedsDisplay()
        }

        override public func draw(_ rect: CGRect) {
            guard let layout, let page else { return }

            layout.draw(page)
        }
    }
}
