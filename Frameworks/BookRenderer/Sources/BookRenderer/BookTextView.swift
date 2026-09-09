//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import SwiftUI

/// A short piece of the book's own text, set by the book's own typesetter.
///
/// The reader's note is what this is for. A note is the book's words rather than the app's, so it is
/// bound, hyphenated and filled the way the page is, in the face and the colours the page is set in.
/// SwiftUI would break its lines on its own rules and could not justify them at all.
public struct BookTextView: View {
    public let text: String
    public let style: ChapterTextStyle
    public let width: CGFloat

    @State
    private var laid: Laid?

    public init(text: String, style: ChapterTextStyle, width: CGFloat) {
        self.text = text
        self.style = style
        self.width = width
    }

    /// A piece of text once it has been set, and how deep it came out.
    private struct Laid {
        let layout: ChapterLayout
        let height: CGFloat
    }

    public var body: some View {
        Group {
            if let laid {
                ChapterPageView(layout: laid.layout, pageIndex: 0)
                    .frame(width: width, height: laid.height)
            } else {
                // A gap the size of one line, so the aside doesn't jump as its text arrives.
                Color.clear.frame(width: width, height: style.fontSize * 2)
            }
        }
        .task(id: text) { await compose() }
    }

    private func compose() async {
        let context = ChapterLayout.Context(
            style: style,
            // Room for the marks the column hangs outside its measure. A page has margins for those to
            // hang into; without any, every line ending in a comma or a hyphen loses that mark off the
            // edge, and the text reads as though it had been cut.
            margins: Self.hang(for: style),
            // Deep enough that everything lands on one page. What is wanted here is the text, not the
            // text cut into pages, and whoever shows this decides how much of it to show.
            pageSize: CGSize(width: width, height: Self.depth),
            safeArea: EdgeInsets(),
            hasRunningHeads: false
        )
        let content = await ChapterContent.prepare(html: Self.markup(text))
        let layout = await ChapterLayout.make(
            chapterId: 0,
            content: content,
            heading: ChapterHeading(),
            context: context
        )

        laid = Laid(layout: layout, height: layout.typesetLines(onPage: 0).reduce(0) { $0 + $1.height })
    }

    /// However long the text runs, it is set as one page.
    private static let depth: CGFloat = 4000

    /// How much of a hanging mark can stand outside the measure, which is a fraction of one character.
    private static func hang(for style: ChapterTextStyle) -> Double { style.fontSize * 0.35 }

    /// The typesetter reads markup, since that is what a chapter arrives as.
    private static func markup(_ text: String) -> String {
        let escaped =
            text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        return "<p>\(escaped)</p>"
    }
}
