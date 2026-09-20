//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookStorage
import Foundation
import OSLog

/// The one-off pass that brings the covers already on the device down to the size one is drawn at.
///
/// Covers a book from a file brought used to be kept exactly as the file carried them, which for a
/// cover made for print is a few megabytes each. They are written at a screen's size now, and this
/// shrinks what was kept before that, once per device.
enum Covers {
    private static let logger = Logger(subsystem: "com.lonelybytes.atreader", category: "covers")

    /// What the covers on this device were last held to, so the pass runs again only if that grows.
    private static let heldTo = "covers.heldTo"

    static func shrinkWhatWasKept() async {
        let held = UserDefaults.standard.integer(forKey: heldTo)

        guard held < CoverCache.maximumPixelSize else { return }

        let shrank = await Task.detached(priority: .utility) { LocalBookFiles.shrinkKeptCovers() }.value

        UserDefaults.standard.set(CoverCache.maximumPixelSize, forKey: heldTo)

        guard shrank > 0 else { return }

        logger.info("shrank \(shrank, privacy: .public) kept covers")
    }
}
