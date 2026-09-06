//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import UIKit

/// The faces offered for the page. Two are system designs, which pick up the reader's dynamic-type
/// and language settings; the rest are classic book faces that ship with iOS.
///
/// The raw values are written into `UserDefaults` and into the key a book's measurements are filed
/// under. Change one and every device silently sets every book again.
public enum BookFace: String, CaseIterable, Identifiable, Sendable {
    case serif
    case system
    case rounded
    case georgia
    case palatino
    case charter
    case stix
    case baskerville
    case hoefler
    case avenir

    public var id: String { rawValue }

    /// The family to ask `UIFont` for, or `nil` when this face is a system design.
    private var familyName: String? {
        switch self {
            case .serif, .system, .rounded: nil
            case .georgia: "Georgia"
            case .palatino: "Palatino"
            case .charter: "Charter"
            case .stix: "STIX Two Text"
            case .baskerville: "Baskerville"
            case .hoefler: "Hoefler Text"
            case .avenir: "Avenir Next"
        }
    }

    private var design: UIFontDescriptor.SystemDesign {
        switch self {
            case .serif: .serif
            case .rounded: .rounded
            default: .default
        }
    }

    /// The weights this face actually ships, in order.
    ///
    /// A face silently gives another cut for a weight it hasn't got: New York has no light, and the
    /// book families carry only a roman and a bold, so asking either of them for medium or semibold
    /// lands on the same bold. Offering a choice that does nothing, or two that do the same thing,
    /// is worse than offering fewer.
    public var weights: [BookWeight] {
        var seen = Set([ resolvedName(.regular) ])

        return BookWeight.allCases.filter { weight in
            weight == .regular || seen.insert(resolvedName(weight.uiWeight)).inserted
        }
    }

    /// What the face calls the cut a weight lands on, so a family doesn't label its own black
    /// "Medium". Hoefler Text has a regular and a black and nothing between; Baskerville's heavier
    /// cut is a semibold; the book families jump straight to bold.
    public func resolvedName(_ weight: UIFont.Weight) -> String { font(size: 16, weight: weight).fontName }

    /// Falls back to the system face when a family is missing, rather than dropping to Helvetica.
    ///
    /// A named family carries only the weights it ships; the descriptor picks the nearest.
    public func font(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
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
///
/// The raw values are persisted and filed under, as ``BookFace``'s are.
public enum BookWeight: String, CaseIterable, Identifiable, Sendable {
    case light
    case regular
    case medium
    case semibold

    public var id: String { rawValue }

    public var uiWeight: UIFont.Weight {
        switch self {
            case .light: .light
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
        }
    }
}
