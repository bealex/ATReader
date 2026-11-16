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
    /// The way round the reader holds the page, or none.
    enum Choice: String, CaseIterable, Identifiable {
        case free
        case portrait
        /// Landscape with the device's top turned to the left.
        case turnedLeft
        /// Landscape with the device's top turned to the right.
        case turnedRight
        case upsideDown

        var id: String { rawValue }

        var title: String {
            switch self {
                case .free: String(localized: "Turns with the device")
                case .portrait: String(localized: "Portrait")
                case .turnedLeft: String(localized: "Landscape, turned left")
                case .turnedRight: String(localized: "Landscape, turned right")
                case .upsideDown: String(localized: "Upside down")
            }
        }

        /// The one way round this holds the page to, nothing for a page that turns.
        var held: UIInterfaceOrientationMask? {
            switch self {
                case .free: nil
                case .portrait: .portrait
                // The interface turns against the device: its top turned left stands the interface's right edge up.
                case .turnedLeft: .landscapeRight
                case .turnedRight: .landscapeLeft
                case .upsideDown: .portraitUpsideDown
            }
        }

        /// What this device offers. A phone upside down puts its own camera at the bottom and won't turn
        /// that way.
        static var offered: [Self] {
            UIDevice.current.userInterfaceIdiom == .pad ? allCases : allCases.filter { $0 != .upsideDown }
        }
    }

    private(set) static var choice: Choice = .free
    /// True while something over the page turns with the device whatever the reader locked.
    private static var isReleased = false

    /// A tablet has no way up of its own, so it may be held any way round.
    static var mask: UIInterfaceOrientationMask {
        if !isReleased, let held = choice.held { return held }

        return UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }

    /// True where the reader's lock stands the page upright, which a wide table has to turn back from.
    static var holdsUpright: Bool { choice == .portrait || choice == .upsideDown }

    /// Called before any scene exists, so it only records the answer.
    static func seed(_ choice: Choice) {
        self.choice = choice
    }

    /// Records the answer and asks the scene to act on it, which turns the page round to it.
    static func apply(_ choice: Choice) {
        self.choice = choice
        settle()
    }

    /// Lets the screen turn with the device until ``hold()``, however the reader locked it.
    static func release() {
        isReleased = true
        settle()
    }

    /// Puts the reader's own lock back, turning the screen round to it.
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

            if !isReleased, let held = choice.held {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: held))
            }
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
