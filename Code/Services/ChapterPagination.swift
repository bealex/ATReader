//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import CoreText
import UIKit

/// Everything about the page that changes how text lays out.
///
/// Pagination and drawing both build their attributed text from this, so the page breaks the reader
/// measures are exactly the ones it draws. Margins are deliberately absent — they shrink the frame the
/// text is laid into rather than the text itself.
struct ChapterTextStyle: Equatable {
    var face: ReaderSettings.Face
    var fontSize: Double
    var lineSpacing: Double
    var isJustified: Bool
    var textColor: UIColor

    var font: UIFont { face.font(size: fontSize) }
}

/// Turns a chapter into fixed-size pages.
enum ChapterPagination {
    /// Builds the chapter as one attributed string, one paragraph per block.
    ///
    /// Centred blocks (scene breaks, epigraphs) keep their own alignment whatever the reader chose —
    /// justifying a one-line epigraph looks like a bug.
    static func attributedText(
        for paragraphs: [ChapterHTML.Paragraph],
        style: ChapterTextStyle
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = style.font
        let bodyAlignment: NSTextAlignment = style.isJustified ? .justified : .natural

        for (index, paragraph) in paragraphs.enumerated() {
            let isCentered = paragraph.isCentered
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = isCentered ? .center : bodyAlignment
            paragraphStyle.lineSpacing = style.lineSpacing
            paragraphStyle.paragraphSpacing = style.lineSpacing * 0.8
            paragraphStyle.firstLineHeadIndent = isCentered ? 0 : font.pointSize
            paragraphStyle.lineBreakMode = .byWordWrapping
            // Justification hyphenates rather than opening rivers of white space in narrow columns.
            paragraphStyle.hyphenationFactor = style.isJustified ? 1 : 0

            let suffix = index == paragraphs.count - 1 ? "" : "\n"
            result.append(NSAttributedString(
                string: paragraph.text + suffix,
                attributes: [
                    .font: font,
                    .foregroundColor: style.textColor,
                    .paragraphStyle: paragraphStyle,
                ]
            ))
        }

        return result
    }

    /// Splits the text into the ranges that fit successive frames of `size`.
    ///
    /// `CTFrameGetVisibleStringRange` reports what actually fitted, so this walks the string a page at a
    /// time rather than guessing from character counts.
    static func pageRanges(in text: NSAttributedString, size: CGSize) -> [NSRange] {
        guard text.length > 0, size.width > 1, size.height > 1 else { return [] }

        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
        var ranges: [NSRange] = []
        var location = 0

        while location < text.length {
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)

            // A page that fits nothing means the frame is too small for even one line; bail rather
            // than spin forever.
            guard visible.length > 0 else { break }

            ranges.append(NSRange(location: location, length: visible.length))
            location += visible.length
        }

        return ranges
    }

    /// The area text is laid into, once the margins are taken out.
    static func textSize(in bounds: CGSize, margins: Double) -> CGSize {
        CGSize(width: max(1, bounds.width - margins * 2), height: max(1, bounds.height - margins * 2))
    }
}
