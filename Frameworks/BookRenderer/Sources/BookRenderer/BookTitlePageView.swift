//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// The page a book opens on: cover, title, author and series, set in the reader's own typeface.
public struct BookTitlePageView: View {
    public let title: String
    public let author: String
    public let seriesTitle: String?
    public let coverURL: URL?
    public let style: ChapterTextStyle
    public let margins: Double
    public let safeArea: EdgeInsets

    public init(
        title: String,
        author: String,
        seriesTitle: String?,
        coverURL: URL?,
        style: ChapterTextStyle,
        margins: Double,
        safeArea: EdgeInsets
    ) {
        self.title = title
        self.author = author
        self.seriesTitle = seriesTitle
        self.coverURL = coverURL
        self.style = style
        self.margins = margins
        self.safeArea = safeArea
    }

    private var foreground: Color { Color(style.textColor) }

    public var body: some View {
        VStack(spacing: 0) {
            PagePicture(url: coverURL, palette: style.palette)
                .padding(.bottom, 32)

            Text(title)
                .font(Font(style.face.font(size: style.fontSize * 1.7, weight: style.weight.uiWeight)))
                .foregroundStyle(foreground)
                .multilineTextAlignment(.center)
                .padding(.bottom, 14)

            Text(author)
                .font(Font(style.face.font(size: style.fontSize, weight: style.weight.uiWeight)))
                .foregroundStyle(foreground.opacity(0.7))
                .multilineTextAlignment(.center)

            if let seriesTitle, !seriesTitle.isEmpty {
                Text(seriesTitle)
                    .font(Font(style.face.font(size: style.fontSize * 0.85, weight: style.weight.uiWeight)))
                    .foregroundStyle(foreground.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.top, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, max(margins, 24))
        .padding(.top, safeArea.top)
        .padding(.bottom, safeArea.bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(seriesTitle.map { "\(title), \(author), \($0)" } ?? "\(title), \(author)")
    }
}
