//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import UIKit

extension View {
    /// Tells `report` the size of the window this view stands in, and again whenever it changes.
    ///
    /// The window's own size rather than the view's: a form in a popover is a fraction of the window it
    /// speaks for.
    func onWindowSize(_ report: @escaping (CGSize) -> Void) -> some View {
        background(WindowSizeProbe(report: report))
    }
}

/// A view of no size, for the window it stands in: SwiftUI hands out no windows.
private struct WindowSizeProbe: UIViewRepresentable {
    let report: (CGSize) -> Void

    func makeUIView(context: Context) -> ProbeView { ProbeView(report: report) }

    func updateUIView(_ view: ProbeView, context: Context) { view.report = report }

    final class ProbeView: UIView {
        var report: (CGSize) -> Void
        private var told: CGSize?

        init(report: @escaping (CGSize) -> Void) {
            self.report = report
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            tell()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            tell()
        }

        private func tell() {
            guard let size = window?.bounds.size, size != told else { return }

            told = size
            // Out of the layout pass: the size is state, and state set while SwiftUI lays out is dropped.
            DispatchQueue.main.async { self.report(size) }
        }
    }
}
