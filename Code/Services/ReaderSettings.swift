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

        var id: String { rawValue }

        var title: String {
            switch self {
                case .system: String(localized: "Match the system")
                case .paper: String(localized: "Paper")
                case .sepia: String(localized: "Sepia")
                case .night: String(localized: "Night")
            }
        }

        var background: Color {
            switch self {
                case .system: Color(.systemBackground)
                case .paper: Color(red: 0.99, green: 0.99, blue: 0.97)
                case .sepia: Color(red: 0.96, green: 0.91, blue: 0.82)
                case .night: Color(red: 0.09, green: 0.09, blue: 0.11)
            }
        }

        var foreground: Color {
            switch self {
                case .system: Color(.label)
                case .paper: Color(red: 0.11, green: 0.11, blue: 0.12)
                case .sepia: Color(red: 0.25, green: 0.19, blue: 0.11)
                case .night: Color(red: 0.85, green: 0.85, blue: 0.88)
            }
        }

        /// Forces the status bar and controls to match the page, except when following the system.
        var colorScheme: ColorScheme? {
            switch self {
                case .system: nil
                case .paper, .sepia: .light
                case .night: .dark
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
        func font(size: CGFloat) -> UIFont {
            let system = UIFont.systemFont(ofSize: size)

            guard
                let familyName
            else {
                guard let descriptor = system.fontDescriptor.withDesign(design) else { return system }

                return UIFont(descriptor: descriptor, size: size)
            }

            return UIFont(name: familyName, size: size) ?? system
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

    var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: Keys.fontSize) }
    }

    var lineSpacing: Double {
        didSet { UserDefaults.standard.set(lineSpacing, forKey: Keys.lineSpacing) }
    }

    /// Page inset in points, applied on every edge.
    var margins: Double {
        didSet { UserDefaults.standard.set(margins, forKey: Keys.margins) }
    }

    var face: Face {
        didSet { UserDefaults.standard.set(face.rawValue, forKey: Keys.face) }
    }

    var alignment: Alignment {
        didSet { UserDefaults.standard.set(alignment.rawValue, forKey: Keys.alignment) }
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
        face = defaults.string(forKey: Keys.face).flatMap(Face.init(rawValue:)) ?? .serif
        alignment = defaults.string(forKey: Keys.alignment).flatMap(Alignment.init(rawValue:)) ?? .justified
        theme = defaults.string(forKey: Keys.theme).flatMap(Theme.init(rawValue:)) ?? .system
    }

    /// Everything the layout engine needs; changing any of it invalidates pagination.
    var textStyle: ChapterTextStyle {
        ChapterTextStyle(
            face: face,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            isJustified: alignment == .justified,
            textColor: UIColor(theme.foreground)
        )
    }

    /// A preview of the current face for the settings sheet.
    var previewFont: Font { Font(face.font(size: fontSize)) }

    private enum Keys {
        static let fontSize = "reader.fontSize"
        static let lineSpacing = "reader.lineSpacing"
        static let margins = "reader.margins"
        static let face = "reader.face"
        static let alignment = "reader.alignment"
        static let theme = "reader.theme"
    }
}
