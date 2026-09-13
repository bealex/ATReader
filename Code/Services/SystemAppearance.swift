//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import UIKit

/// What the system is showing, light or dark.
///
/// Asked of the scene rather than of a window or of SwiftUI's environment, because the reader holds the
/// window to the page's own light or dark for as long as a book is open: a window asked then answers
/// with the page, and a page that follows the system would be following itself. An override reaches
/// down from a window and never up to the scene it is in.
@MainActor
enum SystemAppearance {
    static var isDark: Bool { scene?.traitCollection.userInterfaceStyle == .dark }

    /// True where there is a scene to ask. Without one every answer here is the same answer, which is
    /// worth being able to tell apart from the system being light.
    static var isKnown: Bool { scene != nil }

    /// Whatever the style is now, and whenever it changes. The registration is the caller's to hold:
    /// dropped, it stops.
    static func watch(_ answer: @escaping @MainActor (Bool) -> Void) -> (any UITraitChangeRegistration)? {
        guard let scene else { return nil }

        answer(scene.traitCollection.userInterfaceStyle == .dark)

        return scene.registerForTraitChanges([ UITraitUserInterfaceStyle.self ]) { (scene: UIWindowScene, _) in
            answer(scene.traitCollection.userInterfaceStyle == .dark)
        }
    }

    private static var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene
    }
}
