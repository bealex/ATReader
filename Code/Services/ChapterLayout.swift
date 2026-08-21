//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import SwiftUI
import UIKit

/// One chapter, laid out for one style and one page size.
///
/// TextKit rather than CoreText, because CoreText does not hyphenate: it treats a soft hyphen as a
/// place it may break a word and then draws no hyphen there, which is worse than not breaking at all.
/// `NSLayoutManager` hyphenates from the system's own dictionaries, justifies, and pages the chapter by
/// flowing it through one text container per page.
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

    /// The character range each page covers, so a reading position survives a change of font.
    private(set) var pageRanges: [NSRange] = []

    private let storage: NSTextStorage
    private let manager = NSLayoutManager()
    private var pages: [NSTextContainer] = []

    init(chapterId: Int, text: NSAttributedString, context: Context) {
        self.chapterId = chapterId
        self.context = context
        self.storage = NSTextStorage(attributedString: text)
        storage.addLayoutManager(manager)
    }

    /// Lays a chapter out, a page at a time, yielding between pages so a long chapter never blocks a
    /// page turn. TextKit is not thread-safe, so this stays where the drawing is.
    static func make(
        chapterId: Int,
        content: ChapterContent,
        heading: ChapterHeading,
        context: Context
    ) async -> ChapterLayout {
        let text = ChapterPagination.attributedText(
            for: content.paragraphs,
            heading: heading,
            language: content.language,
            style: context.style
        )
        let layout = ChapterLayout(chapterId: chapterId, text: text, context: context)
        await layout.paginate()
        return layout
    }

    private func paginate() async {
        guard context.isUsable, storage.length > 0 else { return }

        while pageRanges.isEmpty || laidOutGlyphs < manager.numberOfGlyphs {
            guard appendPage() else { return }

            await Task.yield()
        }
    }

    private var laidOutGlyphs = 0

    /// Adds one page and flows as much of what's left into it. False when nothing more fits.
    private func appendPage() -> Bool {
        let container = NSTextContainer(size: context.textSize)
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        manager.ensureLayout(for: container)

        let glyphs = manager.glyphRange(for: container)

        guard glyphs.length > 0 else { return false }

        pages.append(container)
        pageRanges.append(manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil))
        laidOutGlyphs = glyphs.location + glyphs.length
        return true
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

    /// Draws a page where the reader's margins put it.
    func draw(page index: Int) {
        guard pages.indices.contains(index) else { return }

        let glyphs = manager.glyphRange(for: pages[index])
        manager.drawBackground(forGlyphRange: glyphs, at: context.textRect.origin)
        manager.drawGlyphs(forGlyphRange: glyphs, at: context.textRect.origin)
    }

    /// The page's text, for VoiceOver and for the reader's own accessibility label.
    func pageText(_ index: Int) -> String {
        guard pageRanges.indices.contains(index) else { return "" }

        return (storage.string as NSString).substring(with: pageRanges[index])
    }
}
