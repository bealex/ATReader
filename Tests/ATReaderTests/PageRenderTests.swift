//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import Testing
import UIKit

@testable import ATReader

/// Draws pages to PNG so a change to the column can be looked at rather than argued about.
///
/// Name a directory in `TEST_RUNNER_AT_RENDER_DIR` to write them; without it these do nothing. Each
/// page carries a rule down both margins, which is what makes a ragged edge visible at a glance.
/// The settings the pages are drawn at, chosen to span what the column has to cope with: a narrow
/// measure and a wide one, a small face and a large one.
let renderSettings: [Setting] = [
    Setting(face: .serif, size: 19, margins: 24),
    Setting(face: .serif, size: 24, margins: 37),
    Setting(face: .serif, size: 15, margins: 16),
    Setting(face: .system, size: 19, margins: 24),
]

@MainActor
struct PageRenderTests {
    static var directory: String? { ProcessInfo.processInfo.environment["AT_RENDER_DIR"] }

    @Test(arguments: renderSettings)
    func drawsTheRussianCorpus(setting: Setting) async {
        await render(setting: setting, html: RenderingTests.html, name: "corpus")
    }

    @Test(arguments: renderSettings)
    func drawsRunningProse(setting: Setting) async {
        let html = JustificationTests.prose(6)
            .components(separatedBy: "\n")
            .map { "<p>\($0)</p>" }
            .joined()

        await render(setting: setting, html: html, name: "prose")
    }

    /// The dark theme, where the colour has to reach CoreText through a key of its own.
    @Test
    func drawsInTheDark() async {
        var context = JustificationTests.testContext
        context.style.textColor = .white

        await render(context: context, html: RenderingTests.html, name: "corpus", label: "dark", onDark: true)
    }

    /// Every page reported off a device, at the settings it was read at.
    @Test
    func drawsTheReportedPages() async {
        for report in PageReport.all {
            await render(context: report.context, html: report.html, name: "device", label: report.name)
        }
    }

    // MARK: - Drawing

    private func render(setting: Setting, html: String, name: String) async {
        var context = JustificationTests.testContext
        context.style.face = setting.face
        context.style.fontSize = setting.size
        context.margins = setting.margins

        let label = "\(setting.face.rawValue)-\(Int(setting.size))pt-m\(Int(setting.margins))"
        await render(context: context, html: html, name: name, label: label)
    }

    private func render(
        context: ChapterLayout.Context,
        html: String,
        name: String,
        label: String,
        onDark: Bool = false
    ) async {
        guard let directory = Self.directory else { return }

        let layout = await ChapterLayout.make(
            chapterId: 1,
            content: await ChapterContent.prepare(html: html),
            heading: ChapterHeading.make(position: 1, title: "Глава первая"),
            context: context
        )

        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        for page in 0 ..< min(layout.pageCount, 3) {
            let image = draw(page: page, of: layout, context: context, onDark: onDark)
            let file = "\(name)-\(label)-p\(page + 1).png"

            try? image.pngData()?.write(to: URL(fileURLWithPath: directory).appendingPathComponent(file))
        }
    }

    private func draw(
        page: Int,
        of layout: ChapterLayout,
        context: ChapterLayout.Context,
        onDark: Bool
    ) -> UIImage {
        UIGraphicsImageRenderer(size: context.pageSize).image { drawing in
            let rect = CGRect(origin: .zero, size: context.pageSize)
            (onDark ? UIColor.black : UIColor.white).setFill()
            drawing.fill(rect)

            // A rule down each margin: a line that stops short of one shows up without measuring it.
            UIColor.systemRed.withAlphaComponent(0.35).setFill()
            for x in [ context.textRect.minX, context.textRect.maxX ] {
                drawing.fill(CGRect(x: x, y: 0, width: 0.5, height: rect.height))
            }

            layout.draw(page: page)
        }
    }
}
