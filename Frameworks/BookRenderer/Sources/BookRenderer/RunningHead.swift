//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// The book's title above the text, or the page number below it.
///
/// What stands in the band ``ChapterLayout/Context/runningHeadBand`` keeps clear at the head and foot
/// of every page. It lives beside the band rather than with whoever draws the page, so the room kept
/// and the thing kept in it are settled in one place.
///
/// It takes its ink and its size rather than choosing them: the page is set in whatever colours the
/// reader is reading in, and the size comes off the book's own text.
public struct RunningHead: View {
    public enum Edge: Sendable {
        case head
        case foot
    }

    public let text: String
    public let edge: Edge
    public let size: CGFloat
    public let ink: Color
    public let margins: CGFloat
    /// What the device keeps at that edge of the screen, which the page itself reaches past.
    public let deviceInset: CGFloat
    /// The room the layout keeps for it, which it stands in the middle of.
    public let band: CGFloat

    public init(
        text: String,
        edge: Edge,
        size: CGFloat,
        ink: Color,
        margins: CGFloat,
        deviceInset: CGFloat,
        band: CGFloat
    ) {
        self.text = text
        self.edge = edge
        self.size = size
        self.ink = ink
        self.margins = margins
        self.deviceInset = deviceInset
        self.band = band
    }

    public var body: some View {
        Text(text)
            .font(.system(size: size))
            .lineLimit(1)
            .foregroundStyle(ink)
            .padding(.horizontal, margins)
            .padding(.top, edge == .head ? deviceInset + air(band, size) : 0)
            .padding(.bottom, edge == .foot ? deviceInset + air(band, size) : 0)
            .frame(maxWidth: .infinity)
    }

    /// What stands between the head and the edge of its band.
    ///
    /// The middle of the band, not the top of it. The band is deep enough to hold the controls that
    /// stand on the head's line, and a head pinned to the top of it puts that line where a control
    /// centred on it hangs off the screen: a phone lends the notch's depth to cover that, an iPad keeps
    /// nothing at the top and the control is cut off. Centred, the whole of it is always on the page.
    public static func air(_ band: CGFloat, _ size: CGFloat) -> CGFloat {
        max(inset, (band - line(size)) / 2)
    }

    private func air(_ band: CGFloat, _ size: CGFloat) -> CGFloat { Self.air(band, size) }

    /// The least the head keeps between itself and the device's own band.
    public static let inset: CGFloat = 4

    /// The line a head of this size is set on, which is deeper than the type itself.
    public static func line(_ size: CGFloat) -> CGFloat {
        UIFont.systemFont(ofSize: size).lineHeight
    }
}
