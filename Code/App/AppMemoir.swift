//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Memoirs

/// The app's own log roots.
enum AppMemoir {
    /// os_log, under a category per tracer label.
    static let root: Memoir = OSLogMemoir(subsystem: "com.lonelybytes.atreader", isSensitive: false)
}
