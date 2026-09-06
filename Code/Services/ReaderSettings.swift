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
    enum Theme: String, CaseIterable, Identifiable {
        case system
        case paper
        case sepia
        case night
        case green

        var id: String { rawValue }

        var title: String {
            switch self {
                case .system: String(localized: "Match the system")
                case .paper: String(localized: "Paper")
                case .sepia: String(localized: "Sepia")
                case .night: String(localized: "Night")
                case .green: String(localized: "Green")
            }
        }

        var background: Color {
            switch self {
                case .system: Color(.systemBackground)
                case .paper: Color(red: 0.99, green: 0.99, blue: 0.97)
                case .sepia: Color(red: 0.96, green: 0.91, blue: 0.82)
                case .night: Color(red: 0.09, green: 0.09, blue: 0.11)
                case .green: Color(red: 0.02, green: 0.02, blue: 0.02)
            }
        }

        var foreground: Color {
            switch self {
                case .system: Color(.label)
                case .paper: Color(red: 0.11, green: 0.11, blue: 0.12)
                case .sepia: Color(red: 0.25, green: 0.19, blue: 0.11)
                case .night: Color(red: 0.85, green: 0.85, blue: 0.88)
                case .green: Color(red: 0.29, green: 0.63, blue: 0.35)
            }
        }

        /// Forces the status bar and controls to match the page, except when following the system.
        var colorScheme: ColorScheme? {
            switch self {
                case .system: nil
                case .paper, .sepia: .light
                case .night, .green: .dark
            }
        }
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
    static let marginRange: ClosedRange<Double> = 0 ... 100
    /// Tracking in points. A little either way is all a text face can take before it stops reading well.
    static let letterSpacingRange: ClosedRange<Double> = -0.5 ... 2

    var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: Keys.fontSize) }
    }

    var lineSpacing: Double {
        didSet { UserDefaults.standard.set(lineSpacing, forKey: Keys.lineSpacing) }
    }

    /// Space added between letters, in points.
    var letterSpacing: Double {
        didSet { UserDefaults.standard.set(letterSpacing, forKey: Keys.letterSpacing) }
    }

    /// Page inset in points, applied on every edge.
    var margins: Double {
        didSet { UserDefaults.standard.set(margins, forKey: Keys.margins) }
    }

    var face: Face {
        didSet {
            UserDefaults.standard.set(face.rawValue, forKey: Keys.face)
            // A face that hasn't got the weight in hand would silently draw another one.
            if !face.weights.contains(weight) { weight = .regular }
        }
    }

    var weight: Weight {
        didSet { UserDefaults.standard.set(weight.rawValue, forKey: Keys.weight) }
    }

    /// Russian sets well justified: its hyphenation dictionary is good and its words are long enough
    /// to fill a line. English justified in a narrow column pulls the words apart instead.
    var russianAlignment: Alignment {
        didSet { UserDefaults.standard.set(russianAlignment.rawValue, forKey: Keys.russianAlignment) }
    }

    /// Used for every language that isn't Russian.
    var englishAlignment: Alignment {
        didSet { UserDefaults.standard.set(englishAlignment.rawValue, forKey: Keys.englishAlignment) }
    }

    var theme: Theme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme) }
    }

    /// Draws every picture in the page's own two colours, colour art included.
    ///
    /// Line art and scans take them anyway, since a sheet of white paper in the middle of a night page
    /// reads worse than the text around it. This holds the rest to them too.
    var monochromeImages: Bool {
        didSet { UserDefaults.standard.set(monochromeImages, forKey: Keys.monochromeImages) }
    }

    /// Holds the page upright however the device is held, which is what reading lying down asks for.
    var isPortraitOnly: Bool {
        didSet {
            UserDefaults.standard.set(isPortraitOnly, forKey: Keys.portraitOnly)
            OrientationLock.apply(portraitOnly: isPortraitOnly)
        }
    }

    init() {
        let defaults = UserDefaults.standard
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
        theme = defaults.string(forKey: Keys.theme).flatMap(Theme.init(rawValue:)) ?? .system
        monochromeImages = defaults.bool(forKey: Keys.monochromeImages)
        isPortraitOnly = defaults.bool(forKey: Keys.portraitOnly)
        OrientationLock.seed(portraitOnly: isPortraitOnly)
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
        static let monochromeImages = "reader.monochromeImages"
        static let portraitOnly = "reader.portraitOnly"
    }
}
