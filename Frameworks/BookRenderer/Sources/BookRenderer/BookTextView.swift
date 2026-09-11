//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import SwiftUI

/// A stretch picked out the way a finger picks one: from a point on one line to a point on another,
/// opened out to whole words.
public struct BookTextPick: Equatable, Sendable {
    /// The lines the finger starts and stops on, counted from the first.
    public var fromLine: Int
    public var toLine: Int
    /// How far across its line each point stands, from nothing to the whole measure.
    public var fromAcross: CGFloat
    public var toAcross: CGFloat

    public init(fromLine: Int, fromAcross: CGFloat, toLine: Int, toAcross: CGFloat) {
        self.fromLine = fromLine
        self.fromAcross = fromAcross
        self.toLine = toLine
        self.toAcross = toAcross
    }
}

/// A short piece of the book's own text, set by the book's own typesetter.
///
/// The reader's note is what this is for. A note is the book's words rather than the app's, so it is
/// bound, hyphenated and filled the way the page is, in the face and the colours the page is set in.
/// SwiftUI would break its lines on its own rules and could not justify them at all.
public struct BookTextView<Painting: View>: View {
    public let text: String
    public let style: ChapterTextStyle
    public let width: CGFloat
    public let pick: BookTextPick?
    /// What is laid under each box the pick covers, one box a line.
    private let painting: (CGRect) -> Painting

    @State
    private var laid: Laid?

    public init(
        text: String,
        style: ChapterTextStyle,
        width: CGFloat,
        pick: BookTextPick?,
        @ViewBuilder painting: @escaping (CGRect) -> Painting
    ) {
        self.text = text
        self.style = style
        self.width = width
        self.pick = pick
        self.painting = painting
    }

    /// A piece of text once it has been set, how deep it came out, and where its pick stands.
    private struct Laid {
        let layout: ChapterLayout
        let height: CGFloat
        let picked: [CGRect]
    }

    public var body: some View {
        Group {
            if let laid {
                ZStack(alignment: .topLeading) {
                    ForEach(laid.picked.indices, id: \.self) { index in
                        let box = laid.picked[index]

                        painting(box)
                            .frame(width: box.width, height: box.height)
                            .offset(x: box.minX, y: box.minY)
                    }

                    ChapterPageView(layout: laid.layout, pageIndex: 0)
                        .frame(width: width, height: laid.height)
                }
                .frame(width: width, height: laid.height, alignment: .topLeading)
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

        let lines = layout.typesetLines(onPage: 0)

        laid = Laid(
            layout: layout,
            height: lines.reduce(0) { $0 + $1.height },
            picked: picked(in: layout, lines: lines, context: context)
        )
    }

    /// The boxes the pick covers, found the way a finger finds them.
    private func picked(
        in layout: ChapterLayout,
        lines: [ChapterLayout.TypesetLine],
        context: ChapterLayout.Context
    ) -> [CGRect] {
        guard let pick, lines.indices.contains(pick.fromLine), lines.indices.contains(pick.toLine) else { return [] }

        func point(line: Int, across: CGFloat) -> CGPoint {
            let top = context.textRect.minY + lines.prefix(line).reduce(0) { $0 + $1.height }

            return CGPoint(x: context.textRect.minX + context.textSize.width * across, y: top + lines[line].height / 2)
        }

        guard
            let range = layout.words(
                from: point(line: pick.fromLine, across: pick.fromAcross),
                to: point(line: pick.toLine, across: pick.toAcross),
                onPage: 0
            )
        else { return [] }

        return layout.rects(of: range, onPage: 0)
    }

    /// However long the text runs, it is set as one page.
    private static var depth: CGFloat { 4000 }

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

public extension BookTextView where Painting == EmptyView {
    init(text: String, style: ChapterTextStyle, width: CGFloat) {
        self.init(text: text, style: style, width: width, pick: nil) { _ in EmptyView() }
    }
}
