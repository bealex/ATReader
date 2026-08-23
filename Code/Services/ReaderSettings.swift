//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

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

    /// The faces offered for the page. Two are system designs, which pick up the reader's dynamic-type
    /// and language settings; the rest are classic book faces that ship with iOS.
    enum Face: String, CaseIterable, Identifiable {
        case serif
        case system
        case rounded
        case georgia
        case palatino
        case charter

        var id: String { rawValue }

        var title: String {
            switch self {
                case .serif: String(localized: "New York")
                case .system: String(localized: "San Francisco")
                case .rounded: String(localized: "SF Rounded")
                case .georgia: String(localized: "Georgia")
                case .palatino: String(localized: "Palatino")
                case .charter: String(localized: "Charter")
            }
        }

        /// The family to ask `UIFont` for, or `nil` when this face is a system design.
        private var familyName: String? {
            switch self {
                case .serif, .system, .rounded: nil
                case .georgia: "Georgia"
                case .palatino: "Palatino"
                case .charter: "Charter"
            }
        }

        private var design: UIFontDescriptor.SystemDesign {
            switch self {
                case .serif: .serif
                case .rounded: .rounded
                default: .default
            }
        }

        /// Falls back to the system face when a family is missing, rather than dropping to Helvetica.
        ///
        /// A named family carries only the weights it ships; the descriptor picks the nearest.
        func font(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
            let system = UIFont.systemFont(ofSize: size, weight: weight)

            guard
                let familyName
            else {
                guard let descriptor = system.fontDescriptor.withDesign(design) else { return system }

                return UIFont(descriptor: descriptor, size: size)
            }

            let descriptor = UIFontDescriptor(fontAttributes: [
                .family: familyName,
                .traits: [ UIFontDescriptor.TraitKey.weight: weight ],
            ])
            return UIFont(descriptor: descriptor, size: size)
        }
    }

    /// How heavy the page is set. A face reads differently at each of these, and a dark theme takes a
    /// little more weight than a light one.
    enum Weight: String, CaseIterable, Identifiable {
        case light
        case regular
        case medium
        case semibold

        var id: String { rawValue }

        var title: String {
            switch self {
                case .light: String(localized: "Light")
                case .regular: String(localized: "Regular")
                case .medium: String(localized: "Medium")
                case .semibold: String(localized: "Semibold")
            }
        }

        var uiWeight: UIFont.Weight {
            switch self {
                case .light: .light
                case .regular: .regular
                case .medium: .medium
                case .semibold: .semibold
            }
        }
    }

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
        didSet { UserDefaults.standard.set(face.rawValue, forKey: Keys.face) }
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
            textColor: UIColor(theme.foreground)
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
    }
}
