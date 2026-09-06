//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookRenderer
import Foundation

/// What a face and a weight are called in the settings sheet.
///
/// Separate from the faces themselves: what a font is belongs to the typesetter, and what it is called
/// on screen is wording the app translates.
extension BookFace {
    var title: String {
        switch self {
            case .serif: String(localized: "New York")
            case .system: String(localized: "San Francisco")
            case .rounded: String(localized: "SF Rounded")
            case .georgia: String(localized: "Georgia")
            case .palatino: String(localized: "Palatino")
            case .charter: String(localized: "Charter")
            case .stix: String(localized: "STIX Two Text")
            case .baskerville: String(localized: "Baskerville")
            case .hoefler: String(localized: "Hoefler Text")
            case .avenir: String(localized: "Avenir Next")
        }
    }

    /// What this face calls the cut a weight lands on, so a family doesn't label its own black
    /// "Medium". Hoefler Text has a regular and a black and nothing between; Baskerville's heavier cut
    /// is a semibold; the book families jump straight to bold.
    func title(for weight: BookWeight) -> String {
        let name = resolvedName(weight.uiWeight)

        if name.contains("Black") || name.contains("Heavy") { return String(localized: "Black") }
        if name.contains("SemiBold") || name.contains("DemiBold") { return String(localized: "Semibold") }
        if name.contains("Bold") { return String(localized: "Bold") }
        if name.contains("Medium") { return String(localized: "Medium") }
        if name.contains("Light") || name.contains("Thin") { return String(localized: "Light") }

        return weight.title
    }
}

extension BookWeight {
    var title: String {
        switch self {
            case .light: String(localized: "Light")
            case .regular: String(localized: "Regular")
            case .medium: String(localized: "Medium")
            case .semibold: String(localized: "Semibold")
        }
    }
}
