//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookRenderer
import DesignSystem
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Bookhold

/// What the reader sets, and what follows from it: which theme the page takes, whether words may
/// break, and where the two things that have to line up end up.
@MainActor
struct ReaderAppearanceTests {
    /// A settings store of its own, so a test neither reads what the device chose nor writes over it.
    private static func settings(_ stored: [String: Any] = [:]) -> ReaderSettings {
        let defaults = UserDefaults(suiteName: "appearance-\(UUID().uuidString)")!

        for (key, value) in stored { defaults.set(value, forKey: key) }

        return ReaderSettings(defaults: defaults)
    }

    // MARK: - Which theme the page takes

    @Test
    func followingTheSystemTurnsWithIt() {
        let settings = Self.settings()

        settings.followsSystem = true
        settings.lightTheme = .paper
        settings.darkTheme = .night

        settings.systemIsDark = false
        #expect(settings.theme == .paper)

        settings.systemIsDark = true
        #expect(settings.theme == .night)
    }

    @Test
    func notFollowingTheSystemKeepsOneThemeThroughIt() {
        let settings = Self.settings()

        settings.followsSystem = false
        settings.fixedTheme = .sepia

        settings.systemIsDark = false
        #expect(settings.theme == .sepia)

        settings.systemIsDark = true
        #expect(settings.theme == .sepia)
    }

    /// "Match the system" was a theme before it was a switch, and meant the same thing.
    @Test
    func aReaderWhoMatchedTheSystemGoesOnMatchingIt() {
        let settings = Self.settings([ "reader.theme": "system" ])

        #expect(settings.followsSystem)
    }

    @Test
    func aReaderWhoChoseAThemeKeepsIt() {
        let settings = Self.settings([ "reader.theme": "sepia" ])

        #expect(!settings.followsSystem)
        #expect(settings.fixedTheme == .sepia)
        #expect(settings.theme == .sepia)
    }

    @Test
    func afreshThePageFollowsTheSystem() {
        let settings = Self.settings()

        #expect(settings.followsSystem)
        #expect(settings.lightTheme == .paper)
        #expect(settings.darkTheme == .night)
    }

    /// Each theme says which half of the day it is for, which is what the switch turns between and what
    /// the status bar and the controls are held to.
    @Test
    func everyThemeSaysWhichHalfOfTheDayItIsFor() {
        #expect(!ReaderSettings.Theme.paper.isDark)
        #expect(!ReaderSettings.Theme.sepia.isDark)
        #expect(ReaderSettings.Theme.night.isDark)
        #expect(ReaderSettings.Theme.green.isDark)

        for theme in ReaderSettings.Theme.allCases {
            #expect(theme.colorScheme == (theme.isDark ? .dark : .light), "\(theme.rawValue)")
        }
    }

    /// The scene is what is asked, and it has to be there to answer: a lookup that finds nothing says
    /// light for ever, which reads as a page that will not follow the system.
    @Test
    func theSystemIsAskedOfSomethingThatCanAnswer() {
        #expect(SystemAppearance.isKnown)

        let scene = UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene
        let window = scene?.windows.first

        #expect(SystemAppearance.isDark == (window?.traitCollection.userInterfaceStyle == .dark))
    }

    // MARK: - Hyphenation

    @Test
    func hyphenationReachesTheTypesetter() {
        let settings = Self.settings()

        settings.hyphenates = false
        #expect(!settings.textStyle.hyphenates)

        settings.hyphenates = true
        #expect(settings.textStyle.hyphenates)
    }

    /// Turning it off has to throw the measurements away, and turning it on has to leave every book
    /// already measured where it was: the flag is written into the fingerprint only when it is off.
    @Test
    func onlyTurningHyphenationOffChangesWhatALayoutIsFiledUnder() {
        var context = JustificationTests.testContext
        let hyphenated = context.fingerprint

        context.style.hyphenates = false

        #expect(context.fingerprint != hyphenated)
        #expect(context.fingerprint.contains("nohyphens"))
        #expect(!hyphenated.contains("nohyphens"))
    }

    /// And it reaches the column: the same text breaks into different lines with it and without it.
    @Test
    func aChapterSetWithoutHyphensBreaksElsewhere() async {
        let content = await ChapterContent.prepare(html: "<p>\(Self.prose)</p>")
        let hyphenated = await Self.layout(of: content, hyphenates: true)
        let plain = await Self.layout(of: content, hyphenates: false)

        #expect(hyphenated.typesetLines.map(\.text) != plain.typesetLines.map(\.text))
        // A broken word fills the line it is broken on, so the column takes no more lines for it.
        #expect(hyphenated.typesetLines.count <= plain.typesetLines.count)
    }

    private static func layout(of content: ChapterContent, hyphenates: Bool) async -> ChapterLayout {
        var context = JustificationTests.testContext

        context.style.hyphenates = hyphenates

        return await ChapterLayout.make(
            chapterId: 1,
            content: content,
            heading: ChapterHeading(),
            context: context
        )
    }

    /// Ordinary Russian, long enough in the word to give the dictionary something to break.
    private static let prose = String(
        repeating: "Переселенцы рассказывали удивительные подробности путешествия по незнакомому побережью. ",
        count: 12
    )

    // MARK: - A slider's steps

    @Test
    func aStepIsHeldInsideTheRange() {
        #expect(SteppedSlider.settled(-3, in: 0 ... 16, by: 1) == 0)
        #expect(SteppedSlider.settled(99, in: 0 ... 16, by: 1) == 16)
    }

    /// The point of settling: a tenth added ten times is a point, not a point and a hair.
    @Test
    func tenTenthsMakeOne() {
        var value = 0.0

        for _ in 0 ..< 10 {
            value = SteppedSlider.settled(value + 0.1, in: -0.5 ... 2, by: 0.1)
        }

        #expect(abs(value - 1) < 0.000_001)
    }

    @Test
    func aStepLandsOnTheStep() {
        #expect(SteppedSlider.settled(0.96, in: -0.5 ... 2, by: 0.1) == 1)
        #expect(SteppedSlider.settled(18.4, in: 14 ... 30, by: 1) == 18)
    }

    // MARK: - The controls and the running head

    /// The controls and the book's name read as one line across the page, whatever the type is set at.
    @Test
    func theControlsSitOnTheRunningHead() {
        typealias Reader = ReaderScreen.Component

        for safeAreaTop in [ 0.0, 62.0 ] {
            for headSize in [ 14.0, 18.7, 26.0 ] {
                let controls = Reader.controlsTop(under: safeAreaTop, headSize: headSize) + Design.Size.touch / 2
                let head = safeAreaTop + Reader.headInset + Reader.headLine(headSize) / 2

                #expect(abs(controls - head) < 0.000_001, "head \(headSize) under \(safeAreaTop)")
            }
        }
    }
}
