//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookRenderer
import SwiftUI
import UIKit

/// Typography, margins and page tint for the reader, persisted across launches.
@Observable @MainActor
final class ReaderSettings {
    /// A page's two colours. What the reader chooses is one of these for the light hours and one for
    /// the dark, or a single one for both.
    enum Theme: String, CaseIterable, Identifiable {
        case paper
        case sepia
        case night
        case green

        var id: String { rawValue }

        var title: String {
            switch self {
                case .paper: String(localized: "Paper")
                case .sepia: String(localized: "Sepia")
                case .night: String(localized: "Night")
                case .green: String(localized: "Green")
            }
        }

        var background: Color {
            switch self {
                case .paper: Color(red: 0.99, green: 0.99, blue: 0.97)
                case .sepia: Color(red: 0.96, green: 0.91, blue: 0.82)
                case .night: Color(red: 0.09, green: 0.09, blue: 0.11)
                case .green: Color(red: 0.02, green: 0.02, blue: 0.02)
            }
        }

        var foreground: Color {
            switch self {
                case .paper: Color(red: 0.11, green: 0.11, blue: 0.12)
                case .sepia: Color(red: 0.25, green: 0.19, blue: 0.11)
                case .night: Color(red: 0.85, green: 0.85, blue: 0.88)
                case .green: Color(red: 0.29, green: 0.63, blue: 0.35)
            }
        }

        /// True for a page meant to be read in the dark, which is what the system asks for by name.
        var isDark: Bool { self == .night || self == .green }

        /// Holds the status bar and the controls to the page rather than to the system.
        var colorScheme: ColorScheme { isDark ? .dark : .light }
    }

    /// What a face and a weight are belongs to the typesetter; what the reader picked belongs here.
    public typealias Face = BookFace
    public typealias Weight = BookWeight

    /// Left-aligned keeps an even word spacing; justified keeps an even right edge.
    enum Alignment: String, CaseIterable, Identifiable {
        case justified
        case leading

        var id: String { rawValue }

        var title: String {
            switch self {
                case .justified: String(localized: "Justified")
                case .leading: String(localized: "Left-aligned")
            }
        }

        var systemImage: String {
            switch self {
                case .justified: "text.justify"
                case .leading: "text.alignleft"
            }
        }
    }

    static let fontSizeRange: ClosedRange<Double> = 14 ... 30
    static let lineSpacingRange: ClosedRange<Double> = 0 ... 16
    static let marginRange: ClosedRange<Double> = 0 ... 100
    /// Tracking in points. A little either way is all a text face can take before it stops reading well.
    static let letterSpacingRange: ClosedRange<Double> = -0.5 ... 2

    var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: Keys.fontSize) }
    }

    var lineSpacing: Double {
        didSet { defaults.set(lineSpacing, forKey: Keys.lineSpacing) }
    }

    /// Space added between letters, in points.
    var letterSpacing: Double {
        didSet { defaults.set(letterSpacing, forKey: Keys.letterSpacing) }
    }

    /// Page inset in points, applied on every edge.
    var margins: Double {
        didSet { defaults.set(margins, forKey: Keys.margins) }
    }

    var face: Face {
        didSet {
            defaults.set(face.rawValue, forKey: Keys.face)
            // A face that hasn't got the weight in hand would silently draw another one.
            if !face.weights.contains(weight) { weight = .regular }
        }
    }

    var weight: Weight {
        didSet { defaults.set(weight.rawValue, forKey: Keys.weight) }
    }

    /// Russian sets well justified: its hyphenation dictionary is good and its words are long enough
    /// to fill a line. English justified in a narrow column pulls the words apart instead.
    var russianAlignment: Alignment {
        didSet { defaults.set(russianAlignment.rawValue, forKey: Keys.russianAlignment) }
    }

    /// Used for every language that isn't Russian.
    var englishAlignment: Alignment {
        didSet { defaults.set(englishAlignment.rawValue, forKey: Keys.englishAlignment) }
    }

    /// True where the page turns with the system: one theme for its light hours and another for its
    /// dark ones. Off, the page keeps one theme whatever the system is doing.
    var followsSystem: Bool {
        didSet { defaults.set(followsSystem, forKey: Keys.followsSystem) }
    }

    var lightTheme: Theme {
        didSet { defaults.set(lightTheme.rawValue, forKey: Keys.lightTheme) }
    }

    var darkTheme: Theme {
        didSet { defaults.set(darkTheme.rawValue, forKey: Keys.darkTheme) }
    }

    /// The page's theme where it does not follow the system.
    var fixedTheme: Theme {
        didSet { defaults.set(fixedTheme.rawValue, forKey: Keys.theme) }
    }

    /// What the system is showing, told by the screen that is showing it. Not kept: the system says it
    /// afresh every launch, and a stale answer would show as the page opening in the wrong colours.
    var systemIsDark = false

    /// The page's colours, whichever way the reader settled them.
    var theme: Theme {
        guard followsSystem else { return fixedTheme }

        return systemIsDark ? darkTheme : lightTheme
    }

    /// Words may be broken at the end of a line. A justified column reads far better for it: the only
    /// other way to reach the measure is to pull the words apart.
    var hyphenates: Bool {
        didSet { defaults.set(hyphenates, forKey: Keys.hyphenates) }
    }

    /// Draws every picture in the page's own two colours, colour art included.
    ///
    /// Line art and scans take them anyway, since a sheet of white paper in the middle of a night page
    /// reads worse than the text around it. This holds the rest to them too.
    var monochromeImages: Bool {
        didSet { defaults.set(monochromeImages, forKey: Keys.monochromeImages) }
    }

    /// Holds the page upright however the device is held, which is what reading lying down asks for.
    var isPortraitOnly: Bool {
        didSet {
            defaults.set(isPortraitOnly, forKey: Keys.portraitOnly)
            OrientationLock.apply(portraitOnly: isPortraitOnly)
        }
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    private var watching: (any UITraitChangeRegistration)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedSize = defaults.double(forKey: Keys.fontSize)
        let storedSpacing = defaults.double(forKey: Keys.lineSpacing)

        fontSize = storedSize > 0 ? storedSize : 19
        lineSpacing = storedSpacing > 0 ? storedSpacing : 7
        // `double(forKey:)` coerces whatever type the value was stored as, but returns 0 when absent —
        // and 0 is a legitimate margin, so presence has to be checked separately.
        margins = defaults.object(forKey: Keys.margins) == nil ? 24 : defaults.double(forKey: Keys.margins)
        letterSpacing = defaults.double(forKey: Keys.letterSpacing)
        face = defaults.string(forKey: Keys.face).flatMap(Face.init(rawValue:)) ?? .serif
        weight = defaults.string(forKey: Keys.weight).flatMap(Weight.init(rawValue:)) ?? .regular
        russianAlignment =
            defaults.string(forKey: Keys.russianAlignment).flatMap(Alignment.init(rawValue:)) ?? .justified
        englishAlignment =
            defaults.string(forKey: Keys.englishAlignment).flatMap(Alignment.init(rawValue:)) ?? .leading
        // "system" was a theme of its own before it was a switch, and it meant exactly what the switch
        // does. A reader who chose it keeps what they chose.
        let stored = defaults.string(forKey: Keys.theme)

        fixedTheme = stored.flatMap(Theme.init(rawValue:)) ?? .paper
        followsSystem =
            defaults.object(forKey: Keys.followsSystem) == nil
            ? stored == nil || stored == "system"
            : defaults.bool(forKey: Keys.followsSystem)
        lightTheme = defaults.string(forKey: Keys.lightTheme).flatMap(Theme.init(rawValue:)) ?? .paper
        darkTheme = defaults.string(forKey: Keys.darkTheme).flatMap(Theme.init(rawValue:)) ?? .night
        hyphenates = defaults.object(forKey: Keys.hyphenates) == nil || defaults.bool(forKey: Keys.hyphenates)
        monochromeImages = defaults.bool(forKey: Keys.monochromeImages)
        isPortraitOnly = defaults.bool(forKey: Keys.portraitOnly)
        OrientationLock.seed(portraitOnly: isPortraitOnly)
    }

    /// Follows what the system is showing, for as long as this is held.
    func watchTheSystem() {
        guard watching == nil else { return }

        watching = SystemAppearance.watch { [weak self] isDark in self?.systemIsDark = isDark }
    }

    /// Asked again where nothing was there to be asked before, and whenever the app has been away long
    /// enough for the system to have turned without it.
    func readTheSystem() {
        systemIsDark = SystemAppearance.isDark
        watchTheSystem()
    }

    /// Everything the layout engine needs; changing any of it invalidates pagination.
    var textStyle: ChapterTextStyle {
        ChapterTextStyle(
            face: face,
            weight: weight,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            letterSpacing: letterSpacing,
            justifiesRussian: russianAlignment == .justified,
            justifiesEnglish: englishAlignment == .justified,
            hyphenates: hyphenates,
            textColor: UIColor(theme.foreground),
            backgroundColor: UIColor(theme.background),
            monochromeImages: monochromeImages
        )
    }

    /// A preview of the current face for the settings sheet.
    var previewFont: Font { Font(face.font(size: fontSize, weight: weight.uiWeight)) }

    private enum Keys {
        static let fontSize = "reader.fontSize"
        static let lineSpacing = "reader.lineSpacing"
        static let letterSpacing = "reader.letterSpacing"
        static let margins = "reader.margins"
        static let face = "reader.face"
        static let weight = "reader.weight"
        static let russianAlignment = "reader.alignment.ru"
        static let englishAlignment = "reader.alignment.en"
        static let theme = "reader.theme"
        static let followsSystem = "reader.theme.followsSystem"
        static let lightTheme = "reader.theme.light"
        static let darkTheme = "reader.theme.dark"
        static let hyphenates = "reader.hyphenates"
        static let monochromeImages = "reader.monochromeImages"
        static let portraitOnly = "reader.portraitOnly"
    }
}
