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

    /// Cyrillic decides the language, so a chapter the recogniser reads as a neighbouring language
    /// still gets the Russian rules.
    @Test(arguments: [
        "Глава первая",
        "Часть III. Стажер",
        "— Ты куда? — спросил он. — Домой.",
        "Глава 12. 1957 год, посёлок Северный.",
        "Виталий читал Sixty Days и думал о Луне.",
    ])
    func cyrillicIsReadAsRussian(text: String) async {
        let language = await ChapterContent.prepare(html: "<p>\(text)</p>").language

        #expect(Typography.isRussian(language), "\(text) came back as \(language ?? "nil")")
    }

    /// The rule must not drag English prose into the Russian settings.
    @Test
    func englishProseIsNotReadAsRussian() async {
        let english = """
            The house stood at the edge of the village, and the road ran straight into the woods. \
            In the morning it was quiet there, and the wind moved the tops of the old pines.
            """
        let language = await ChapterContent.prepare(html: "<p>\(english)</p>").language

        #expect(!Typography.isRussian(language), "English came back as \(language ?? "nil")")
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
