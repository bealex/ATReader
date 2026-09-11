//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// What the app holds back until it is finished. Off unless asked for with a launch argument, which is
/// how the UI tests over it still reach it.
enum Unfinished {
    /// The service's catalogue: the charts tab, and search beyond the reader's own library.
    /// `-at-show-catalogue YES`.
    static var showsCatalogue: Bool { UserDefaults.standard.bool(forKey: "at-show-catalogue") }
}
