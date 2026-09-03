//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import Testing
import UIKit

@testable import ATReader

/// What must hold of a set page whatever it is set with.
///
/// Every rule here is checked against each face, size and margin in turn, because the defects this
/// suite exists for showed at one setting and not another.
/// One combination of the settings a reader can choose.
struct Setting: CustomStringConvertible, Sendable {
    var face: ReaderSettings.Face
    var size: Double
    var margins: Double

    var description: String { "\(face.rawValue) \(Int(size))pt margins \(Int(margins))" }
}

/// Every combination the rendering rules are checked against.
let renderingSettings: [Setting] = ReaderSettings.Face.allCases.flatMap { face in
    [ 15.0, 19.0, 24.0 ].flatMap { size in
        [ 16.0, 37.0 ].map { Setting(face: face, size: size, margins: $0) }
    }
}

@MainActor
struct RenderingTests {

    /// Russian prose written for these tests, shaped to carry what the column has rules about: speech
    /// opening on a dash, short prepositions the binder ties, long words, figures, and marks that hang.
    static let corpus = [
        "Дорога от деревни уходила в лес и терялась среди старых сосен у самой реки, где начинался туман",
        "— Ты куда собрался на ночь глядя? — спросил старик, не оборачиваясь от окна",
        "К вечеру поднялся ветер, и над полем потянулись низкие серые облака, обещавшие долгий дождь",
        "Он насчитал 47 ступеней, поднялся на 3 этаж и остановился у двери с номером 12",
        "Достопримечательность эта, по свидетельству путеводителя, была построена в прошлом столетии",
        "«Я вернусь до темноты», — сказал он и, не дожидаясь ответа, вышел за ворота",
        "В доме было тихо, только на кухне негромко переговаривались о завтрашней поездке в город",
        "Электрификация сельскохозяйственных территорий продвигалась медленнее, чем предполагалось",
    ]

    static var html: String { corpus.map { "<p>\($0).</p>" }.joined() }

    // MARK: - The rules

    /// Nothing the reader wrote may be lost or doubled on the way to the page.
    @Test(arguments: renderingSettings)
    func thePageCarriesEveryWord(setting: Setting) async {
        let layout = await layout(setting)
        let lines = layout.typesetLines.filter { !$0.isHeading }.map(\.text).joined()
        let set = Self.plain(lines)
        let source = Self.plain(Self.corpus.map { "\($0)." }.joined(separator: " "))

        #expect(set == source)
    }

    /// A line may set a mark outside the measure, and nothing else.
    @Test(arguments: renderingSettings)
    func noLineOverrunsItsMeasure(setting: Setting) async {
        let layout = await layout(setting)
        let measure = context(setting).textSize.width
        let hang = setting.size
        let over = layout.typesetLines.filter { $0.width > measure + hang }

        #expect(over.isEmpty, "\(over.count) line(s) past the measure of \(Int(measure))pt")
    }

    /// One paragraph in, one paragraph out, however the lines fall.
    @Test(arguments: renderingSettings)
    func everyParagraphEndsExactlyOnce(setting: Setting) async {
        let layout = await layout(setting)
        let endings = layout.typesetLines.filter { $0.endsParagraph && !$0.isHeading }.count

        #expect(endings == Self.corpus.count)
    }

    /// A line that stops short of its measure says why.
    ///
    /// The column is the only place that knows: a gap held by the dash of speech, a pair the binder
    /// tied, a gap wider than it will open. Asked from outside, the answer has to be guessed at.
    @Test(arguments: renderingSettings)
    func everyShortLineHasAReason(setting: Setting) async {
        let layout = await layout(setting)
        let measure = context(setting).textSize.width
        let unexplained = layout.typesetLines
            .filter { $0.isJustified && !$0.isHeading && !$0.endsParagraph }
            .filter { $0.width < measure * 0.96 && $0.shortReason == nil }

        #expect(unexplained.isEmpty, "\(unexplained.count) line(s) short with no reason given")
    }

    /// A page holds its lines: none is drawn twice, none is dropped between the pages.
    @Test(arguments: renderingSettings)
    func thePagesCoverEveryLineOnce(setting: Setting) async {
        let layout = await layout(setting)
        let counted = (0 ..< layout.pageCount).reduce(0) { $0 + layout.typesetLines(onPage: $1).count }

        #expect(counted == layout.typesetLines.count)
    }

    // MARK: - Setting the page

    private func context(_ setting: Setting) -> ChapterLayout.Context {
        var context = JustificationTests.testContext
        context.style.face = setting.face
        context.style.fontSize = setting.size
        context.margins = setting.margins
        return context
    }

    private func layout(_ setting: Setting) async -> ChapterLayout {
        await ChapterLayout.make(
            chapterId: 1,
            content: await ChapterContent.prepare(html: Self.html),
            heading: ChapterHeading.make(position: 1, title: "Глава первая"),
            context: context(setting)
        )
    }

    /// The text with everything the typesetter added to it taken back out.
    private static func plain(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00AD}", with: "")
            .replacingOccurrences(of: "\u{2060}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            // Freeing a tie leaves this beside the space, which stays where it was.
            .replacingOccurrences(of: "\u{200B}", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
