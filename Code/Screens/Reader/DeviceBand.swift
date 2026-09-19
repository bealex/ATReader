//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// Where the system stands its own bar, and so where the reader's controls stand: across the top, or
/// down the side a folding screen keeps its vertical bar on.
///
/// Asked of the system, since the bar's inset comes and goes with the status bar.
enum DeviceBand: Equatable {
    case top
    case leading
    case trailing

    /// - Parameter barEdge: the edge the system's vertical bar is on, nil where it keeps none.
    init(barEdge: HorizontalEdge?) {
        switch barEdge {
            case .leading: self = .leading
            case .trailing: self = .trailing
            case nil: self = .top
        }
    }

    /// The edge the reader's controls are hung from.
    var alignment: Alignment {
        switch self {
            case .top: .top
            case .leading: .leading
            case .trailing: .trailing
        }
    }

    var isDownASide: Bool { self != .top }

    /// The insets a page is set against, which leave the bar's own column out.
    ///
    /// The bar goes away with the reader's controls and takes its inset with it, so a page that made
    /// room for it would be set again at every tap.
    func pageInsets(from insets: EdgeInsets) -> EdgeInsets {
        var page = insets

        switch self {
            case .top: break
            case .leading: page.leading = 0
            case .trailing: page.trailing = 0
        }

        return page
    }
}

extension View {
    /// Tells `action` which edge the system's vertical bar is on, now and whenever it changes.
    @ViewBuilder
    func onVerticalBarEdge(_ action: @escaping (HorizontalEdge?) -> Void) -> some View {
        if #available(iOS 27.1, *) {
            modifier(VerticalBarEdgeReader(action: action))
        } else {
            self
        }
    }
}

@available(iOS 27.1, *)
private struct VerticalBarEdgeReader: ViewModifier {
    @Environment(\.toolbarVerticalEdge)
    private var edge

    let action: (HorizontalEdge?) -> Void

    func body(content: Content) -> some View {
        content.onChange(of: edge, initial: true) { _, edge in action(edge) }
    }
}
