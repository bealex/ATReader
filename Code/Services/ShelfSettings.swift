//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import SwiftUI

/// What the shelf shows about a book beyond the book itself.
@Observable @MainActor
final class ShelfSettings {
    /// Whether a book carries how many people liked it.
    ///
    /// Off unless asked for: a shelf is what the reader owns and where they are in it, and a popularity
    /// count is the service talking about other people.
    var showsLikes: Bool {
        didSet { UserDefaults.standard.set(showsLikes, forKey: Keys.showsLikes) }
    }

    init() {
        showsLikes = UserDefaults.standard.bool(forKey: Keys.showsLikes)
    }

    private enum Keys {
        static let showsLikes = "shelf.showsLikes"
    }
}
