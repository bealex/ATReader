//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import CoreText
import UIKit

public extension NSAttributedString.Key {
    /// The place in the book a stretch of words points at, carried by the words themselves.
    static let bookLink = NSAttributedString.Key("ATBookLink")
}

/// A link a finger found: where it points, and the words it was written on.
public struct LinkHit: Sendable {
    /// The name the whole book knows the place by.
    public let target: String
    /// Where the words sit in the page's own coordinates.
    public let rect: CGRect

    public init(target: String, rect: CGRect) {
        self.target = target
        self.rect = rect
    }
}
