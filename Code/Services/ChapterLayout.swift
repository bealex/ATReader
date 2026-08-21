//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import CoreText
import UIKit

/// One chapter, laid out for one style and one page size.
///
/// The layout owns the typesetter as well as the page breaks, so every page of a chapter is drawn from
/// the same `CTFramesetter` that measured it. Frames are built once and kept, which is what lets a
/// reader tap through pages faster than they can be typeset.
@MainActor
final class ChapterLayout {
    /// How the pages of a chapter are laid out, before any text is fetched.
    struct Context: Equatable {
        var style: ChapterTextStyle
        var margins: Double
        var pageSize: CGSize

        var textSize: CGSize { ChapterPagination.textSize(in: pageSize, margins: margins) }

        var isUsable: Bool { pageSize.width > 1 && pageSize.height > 1 }
    }

    let chapterId: Int
    let context: Context
    let text: NSAttributedString
    let pageRanges: [NSRange]

    private let framesetter: CTFramesetter
    private var frames: [Int: CTFrame] = [:]

    /// The rectangle text is drawn into, in the page view's own coordinates.
    let textRect: CGRect

    init(chapterId: Int, text: NSAttributedString, pageRanges: [NSRange], context: Context) {
        self.chapterId = chapterId
        self.text = text
        self.pageRanges = pageRanges
        self.context = context
        self.framesetter = CTFramesetterCreateWithAttributedString(text)
        self.textRect = CGRect(origin: .zero, size: context.pageSize)
            .insetBy(dx: context.margins, dy: context.margins)
    }

    /// Lays a chapter out, keeping the typesetting off the main actor.
    static func make(
        chapterId: Int,
        paragraphs: [ChapterHTML.Paragraph],
        heading: ChapterHeading,
        context: Context
    ) async -> ChapterLayout {
        let language = ChapterPagination.language(of: paragraphs)
        let ranges = await ChapterPagination.pageRanges(
            for: paragraphs,
            heading: heading,
            language: language,
            style: context.style,
            size: context.textSize
        )
        let text = ChapterPagination.attributedText(
            for: paragraphs,
            heading: heading,
            language: language,
            style: context.style
        )
        return ChapterLayout(chapterId: chapterId, text: text, pageRanges: ranges, context: context)
    }

    var pageCount: Int { pageRanges.count }

    var isEmpty: Bool { pageRanges.isEmpty }

    /// The page a character offset falls on, so a change of font keeps the reader's place.
    func pageIndex(containing offset: Int) -> Int {
        pageRanges.firstIndex { NSLocationInRange(offset, $0) } ?? max(0, min(offset, pageCount - 1))
    }

    func characterOffset(ofPage index: Int) -> Int {
        pageRanges.indices.contains(index) ? pageRanges[index].location : 0
    }

    /// The typeset page, built on first use and kept for the pages around wherever the reader is.
    func frame(forPage index: Int) -> CTFrame? {
        guard pageRanges.indices.contains(index) else { return nil }

        if let existing = frames[index] { return existing }
        guard textRect.width > 1, textRect.height > 1 else { return nil }

        let range = pageRanges[index]
        let path = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: range.location, length: range.length),
            path,
            nil
        )
        frames[index] = frame
        return frame
    }

    /// Typesets the pages around `index` ahead of the reader reaching them, and drops the ones left behind.
    func prepare(around index: Int, radius: Int = 2) {
        let window = (index - radius) ... (index + radius)
        frames = frames.filter { window.contains($0.key) }

        for page in window { _ = frame(forPage: page) }
    }

    /// The page's text, for VoiceOver and for the reader's own accessibility label.
    func pageText(_ index: Int) -> String {
        guard pageRanges.indices.contains(index) else { return "" }

        return (text.string as NSString).substring(with: pageRanges[index])
    }
}
