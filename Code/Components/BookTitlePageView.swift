//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// The page a book opens on: cover, title, author and series, set in the reader's own typeface.
struct BookTitlePageView: View {
    let title: String
    let author: String
    let seriesTitle: String?
    let coverURL: URL?
    let style: ChapterTextStyle
    let margins: Double
    let safeArea: EdgeInsets

    private var foreground: Color { Color(style.textColor) }

    var body: some View {
        VStack(spacing: 0) {
            CoverImage(url: coverURL, width: 150)
                .padding(.bottom, 32)

            Text(title)
                .font(Font(style.face.font(size: style.fontSize * 1.7)))
                .foregroundStyle(foreground)
                .multilineTextAlignment(.center)
                .padding(.bottom, 14)

            Text(author)
                .font(Font(style.face.font(size: style.fontSize)))
                .foregroundStyle(foreground.opacity(0.7))
                .multilineTextAlignment(.center)

            if let seriesTitle, !seriesTitle.isEmpty {
                Text(seriesTitle)
                    .font(Font(style.face.font(size: style.fontSize * 0.85)))
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
