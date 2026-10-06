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
    /// True while something over the page turns with the device whatever the reader locked.
    private static var isReleased = false

    /// A tablet has no way up of its own, so it may be held any way round. A phone upside down puts
    /// its own camera at the bottom and is left out.
    static var mask: UIInterfaceOrientationMask {
        guard !isPortraitOnly || isReleased else { return .portrait }

        return UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }

    /// Called before any scene exists, so it only records the answer.
    static func seed(portraitOnly: Bool) {
        isPortraitOnly = portraitOnly
    }

    /// Records the answer and asks the scene to act on it, which turns a landscape page back upright.
    static func apply(portraitOnly: Bool) {
        isPortraitOnly = portraitOnly
        settle()
    }

    /// Lets the screen turn with the device until ``hold()``, however the reader locked it.
    static func release() {
        isReleased = true
        settle()
    }

    /// Puts the reader's own lock back, turning the screen upright where it was locked so.
    static func hold() {
        isReleased = false
        settle()
    }

    /// Asks every controller on screen again, in every window and the presented ones included, since
    /// the topmost is the one the system turns with.
    private static func settle() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                var controller = window.rootViewController

                while let asked = controller {
                    asked.setNeedsUpdateOfSupportedInterfaceOrientations()
                    controller = asked.presentedViewController
                }
            }

            if mask == .portrait { scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) }
        }
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
