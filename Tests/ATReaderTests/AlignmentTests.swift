//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import Testing
import UIKit

@testable import ATReader

/// Justification is settled per language, so the setting only reaches the page if the chapter's
/// language is recognised first.
@MainActor
struct AlignmentTests {
    /// Plain Russian sentences, written for this test rather than taken from a book.
    static let russian = """
        Дом стоял на краю деревни, и дорога от него уходила прямо в лес. \
        Утром там было тихо, только ветер качал верхушки старых сосен. \
        Мальчик вышел за ворота, посмотрел на небо и пошёл вниз по тропинке. \
        Вода в реке была холодной, а на другом берегу начинался густой туман. \
        Он вспомнил, что обещал вернуться домой до темноты, и ускорил шаг.
        """

    private func content() async -> ChapterContent {
        await ChapterContent.prepare(html: "<p>\(Self.russian)</p><p>\(Self.russian)</p>")
    }

    private func context(justifiesRussian: Bool) -> ChapterLayout.Context {
        var context = JustificationTests.testContext
        context.style.justifiesRussian = justifiesRussian
        context.style.justifiesEnglish = false
        return context
    }

    private func layout(_ content: ChapterContent, _ context: ChapterLayout.Context) async -> ChapterLayout {
        await ChapterLayout.make(
            chapterId: 1,
            content: content,
            heading: ChapterHeading.make(position: 1, title: nil),
            context: context
        )
    }

    @Test
    func russianProseIsRecognisedAsRussian() async {
        let language = await content().language

        #expect(Typography.isRussian(language))
    }

    /// The English setting is left off, so only the Russian one can be answering.
    @Test
    func theRussianSettingJustifiesRussianProse() async {
        let content = await content()
        let body = await layout(content, context(justifiesRussian: true)).typesetLines.filter { !$0.isHeading }

        let justified = body.filter(\.isJustified).count

        #expect(!body.isEmpty)
        #expect(justified == body.count, "\(justified) of \(body.count) lines justified")
    }

    @Test
    func turningItOffLeavesTheProseRagged() async {
        let content = await content()
        let body = await layout(content, context(justifiesRussian: false)).typesetLines.filter { !$0.isHeading }

        let justified = body.filter(\.isJustified).count

        #expect(!body.isEmpty)
        #expect(justified == 0, "\(justified) lines were justified with the setting off")
    }

    /// Measurements are kept against the setting, so the two must not share a key.
    @Test
    func theSettingChangesTheLayoutFingerprint() {
        #expect(context(justifiesRussian: true).fingerprint != context(justifiesRussian: false).fingerprint)
    }
}
