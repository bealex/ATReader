//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// Which edge the device keeps its own band on: the notch, the camera, the home indicator.
///
/// Read off the window's insets rather than off the orientation, since a folding device can hold its
/// band down one side while the window itself stands upright, and nothing about the orientation says
/// so. A phone turned on its side has the same inset at either edge and keeps its controls at the top,
/// which is where they have always been.
enum DeviceBand: Equatable {
    case top
    case leading
    case trailing

    /// Where the band is, from the window's own insets and the shape of the window it is on.
    ///
    /// Two things have to hold. One side's inset must clearly beat the other's, which rules out the
    /// rounding every corner has. And the window must stand upright, because a band running along one
    /// physical edge of the device is at the head or the foot of a window that is turned on its side,
    /// and the head is where the controls already are.
    static func read(_ insets: EdgeInsets, in window: CGSize) -> DeviceBand {
        guard window.height >= window.width else { return .top }
        guard abs(insets.leading - insets.trailing) >= Self.tellingApart else { return .top }

        return insets.leading > insets.trailing ? .leading : .trailing
    }

    /// The corner the reader's controls are hung from.
    var alignment: Alignment {
        switch self {
            case .top: .top
            case .leading: .leading
            case .trailing: .trailing
        }
    }

    var isDownASide: Bool { self != .top }

    /// How much deeper one side's inset has to be than the other's before it reads as the band rather
    /// than as the rounding of a corner.
    private static let tellingApart: CGFloat = 12
}
