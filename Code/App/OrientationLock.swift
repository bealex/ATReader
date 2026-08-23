//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import UIKit

/// Whether the app may turn with the device, and the means of telling the system when that changes.
///
/// SwiftUI has no modifier for this: the answer comes from the app delegate, which is asked for a mask
/// rather than told one, so the setting is kept here where the delegate can read it.
@MainActor
enum OrientationLock {
    private(set) static var isPortraitOnly = false

    static var mask: UIInterfaceOrientationMask { isPortraitOnly ? .portrait : .allButUpsideDown }

    /// Called before any scene exists, so it only records the answer.
    static func seed(portraitOnly: Bool) {
        isPortraitOnly = portraitOnly
    }

    /// Records the answer and asks the scene to act on it, which turns a landscape page back upright.
    static func apply(portraitOnly: Bool) {
        isPortraitOnly = portraitOnly

        let scene = UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene
        scene?.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()

        guard portraitOnly else { return }

        scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
    }
}

/// The delegate exists for one question: which way round the app may be.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { OrientationLock.mask }
    }
}
