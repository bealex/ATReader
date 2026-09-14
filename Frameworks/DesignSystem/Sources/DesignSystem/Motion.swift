//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import SwiftUI

/// How far the app's timings are stretched, which is one outside a test.
///
/// A screenshot takes longer to make than any of these animations runs for, so a test photographing one
/// catches nothing but the end of it. `-at-motion-scale 12` slows them all down until they can be
/// photographed, without changing what is being watched.
enum MotionScale {
    static var factor: Double {
        let asked = UserDefaults.standard.double(forKey: "at-motion-scale")

        return asked > 0 ? asked : 1
    }
}

/// How a book turns from its edge to its face, and back.
///
/// No bounce: a cover swinging past flat and settling back is a hinge nothing is holding.
public enum FoldMotion {
    public static var turning: Animation { .smooth(duration: turningSeconds) }

    public static var turningSeconds: Double { 0.45 * MotionScale.factor }
}

/// How a picture drawn in the background arrives over the stand-in it replaces: quick enough not to be
/// waited on, slow enough not to flash.
public enum ArrivalMotion {
    public static var fadeSeconds: Double { 0.18 * MotionScale.factor }
}

/// How a card leaves the list: its bookcase shuts over the books, then the shut case goes.
public enum LeaveMotion {
    public static var seconds: Double { 1.1 * MotionScale.factor }

    /// How much of that the case spends shutting, the rest of it spent going.
    public static let shutting: CGFloat = 0.6

    /// How much of the shutting the books take to go, so the case closes on an empty shelf.
    public static let emptying: CGFloat = 0.5
}

/// How a run from nought to one is eased, for what is animated against a clock rather than by an animator.
public enum Easing {
    /// A critically damped spring, normalised so it arrives exactly.
    public static func settling(_ ran: CGFloat) -> CGFloat {
        let shape = { (time: CGFloat) in 1 - (1 + 8 * time) * exp(-8 * time) }

        return shape(ran) / shape(1)
    }
}
