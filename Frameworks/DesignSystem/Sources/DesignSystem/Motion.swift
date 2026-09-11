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
