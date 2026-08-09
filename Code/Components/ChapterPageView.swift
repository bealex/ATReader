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
    let text: NSAttributedString
    let range: NSRange
    let margins: Double

    func makeUIView(context: Context) -> PageView {
        let view = PageView()
        view.backgroundColor = .clear
        view.isOpaque = false
        return view
    }

    func updateUIView(_ view: PageView, context: Context) {
        view.apply(text: text, range: range, margins: margins)
    }

    /// The drawing surface. Keeps its framesetter between draws — rebuilding one per frame while a page
    /// turn is animating is the difference between smooth and not.
    final class PageView: UIView {
        private var text: NSAttributedString?
        private var range = NSRange(location: 0, length: 0)
        private var margins: Double = 0
        private var framesetter: CTFramesetter?

        func apply(text: NSAttributedString, range: NSRange, margins: Double) {
            let textChanged = self.text != text

            if textChanged {
                self.text = text
                framesetter = CTFramesetterCreateWithAttributedString(text)
            }

            guard textChanged || range != self.range || margins != self.margins else { return }

            self.range = range
            self.margins = margins
            updateAccessibility()
            setNeedsDisplay()
        }

        /// Drawn text is invisible to VoiceOver, so the page publishes its own contents as one element.
        private func updateAccessibility() {
            guard let text, range.location >= 0, range.location + range.length <= text.length else { return }

            isAccessibilityElement = true
            accessibilityTraits = .staticText
            accessibilityLabel = (text.string as NSString).substring(with: range)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            setNeedsDisplay()
        }

        override func draw(_ rect: CGRect) {
            guard let framesetter, let context = UIGraphicsGetCurrentContext(), range.length > 0 else { return }

            let inset = CGRect(origin: .zero, size: bounds.size).insetBy(dx: margins, dy: margins)

            guard inset.width > 1, inset.height > 1 else { return }

            // CoreText draws bottom-up; flip into UIKit's coordinate space.
            context.textMatrix = .identity
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)

            let path = CGPath(rect: inset, transform: nil)
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: range.location, length: range.length),
                path,
                nil
            )
            CTFrameDraw(frame, context)
        }
    }
}
