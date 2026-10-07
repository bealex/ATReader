//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookRenderer
import SwiftUI
import Testing
import UIKit

@testable import Bookhold

/// A page takes its colours when it is drawn, so one layout serves every theme.
@MainActor
struct PageInkTests {
    @Test
    func oneLayoutDrawsInWhicheverInkItIsHanded() async {
        let layout = await Self.layout()
        let night = PagePalette(foreground: .white, background: .black, isMonochrome: false)

        // Set in black, as every test page is; on white it is the darkest thing there.
        #expect(Self.extremes(of: layout, palette: nil, paper: .white).darkest < 0.2)
        // The same lines, handed white ink: nothing darker than the paper, and white on it.
        #expect(Self.extremes(of: layout, palette: night, paper: .black).lightest > 0.8)
        // Black ink would have left a black page untouched.
        #expect(Self.extremes(of: layout, palette: nil, paper: .black).lightest < 0.2)
    }

    @Test
    func theThemeIsNoPartOfHowAPageIsSet() {
        let settings = ReaderSettings(defaults: UserDefaults(suiteName: "ink-\(UUID().uuidString)")!)

        settings.followsSystem = true
        settings.systemIsDark = false

        let light = settings.layoutStyle

        settings.systemIsDark = true

        #expect(settings.layoutStyle == light)
        #expect(settings.textStyle.palette.isDark)
    }

    private static func layout() async -> ChapterLayout {
        await ChapterLayout.make(
            chapterId: 1,
            content: await ChapterContent.prepare(html: "<p>Lorem ipsum dolor sit amet consectetur adipiscing.</p>"),
            heading: ChapterHeading.make(position: 1, title: "Lorem"),
            context: JustificationTests.testContext
        )
    }

    /// The darkest and the lightest the page gets, as brightness from nought to one.
    private static func extremes(
        of layout: ChapterLayout,
        palette: PagePalette?,
        paper: UIColor
    ) -> (darkest: CGFloat, lightest: CGFloat) {
        let size = JustificationTests.testContext.pageSize
        let format = UIGraphicsImageRendererFormat()

        format.scale = 1
        // Eight bits a channel, whatever the screen: the bytes are read as that below.
        format.preferredRange = .standard

        let image = UIGraphicsImageRenderer(size: size, format: format).image { drawing in
            paper.setFill()
            drawing.fill(CGRect(origin: .zero, size: size))
            layout.draw(layout.pages[0], palette: palette)
        }

        guard let data = image.cgImage?.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return (1, 0) }

        var darkest: CGFloat = 1
        var lightest: CGFloat = 0

        for pixel in stride(from: 0, to: CFDataGetLength(data), by: 4) {
            let level = (CGFloat(bytes[pixel]) + CGFloat(bytes[pixel + 1]) + CGFloat(bytes[pixel + 2])) / 765

            darkest = min(darkest, level)
            lightest = max(lightest, level)
        }

        return (darkest, lightest)
    }
}
