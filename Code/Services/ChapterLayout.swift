//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import CoreText
import SwiftUI
import UIKit

/// One chapter, laid out for one style and one page size.
///
/// The layout owns the typesetter as well as the page breaks, so every page of a chapter is drawn from
/// the same `CTFramesetter` that measured it. Frames are built once and kept, which is what lets a
/// reader tap through pages faster than they can be typeset.
@MainActor
final class ChapterLayout {
    /// How the pages of a chapter are laid out, before any text is fetched.
    ///
    /// A page fills the screen, so the text has to keep clear of the notch and the home indicator as
    /// well as of the reader's own margins.
    struct Context: Equatable {
        var style: ChapterTextStyle
        var margins: Double
        var pageSize: CGSize
        var safeArea: EdgeInsets

        /// The band kept at the top and bottom of every page for the book title and the page number.
        static let runningHeadHeight: CGFloat = 22

        /// Where the body text is laid out and drawn, in the page's own coordinates.
        var textRect: CGRect {
            CGRect(origin: .zero, size: pageSize).inset(by: UIEdgeInsets(
                top: safeArea.top + margins + Self.runningHeadHeight,
                left: safeArea.leading + margins,
                bottom: safeArea.bottom + margins + Self.runningHeadHeight,
                right: safeArea.trailing + margins
            ))
        }

        var textSize: CGSize { textRect.size }

        var isUsable: Bool { textRect.width > 1 && textRect.height > 1 }
    }

    let chapterId: Int
    let context: Context
    let text: NSAttributedString
    let pageRanges: [NSRange]

    private let framesetter: CTFramesetter
    private var frames: [Int: CTFrame] = [:]

    /// Where CoreText lays the page out. Its own coordinates run bottom-up, so this is the drawing
    /// rectangle flipped.
    private let pathRect: CGRect

    init(chapterId: Int, text: NSAttributedString, pageRanges: [NSRange], context: Context) {
        self.chapterId = chapterId
        self.text = text
        self.pageRanges = pageRanges
        self.context = context
        self.framesetter = CTFramesetterCreateWithAttributedString(text)

        let rect = context.textRect
        self.pathRect = CGRect(
            x: rect.minX,
            y: context.pageSize.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
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
        guard pathRect.width > 1, pathRect.height > 1 else { return nil }

        let range = pageRanges[index]
        let path = CGPath(rect: pathRect, transform: nil)
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
