//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import UIKit

/// How much of the window the keyboard covers, for chrome the safe area doesn't reach.
///
/// An overlay is laid out in the frame of what it covers, so an overlay over a view that turned the
/// safe area down has the window's own foot for a bottom and is never lifted by anything.
///
/// What the keyboard reaches is asked of the keyboard, and asked as an overlap rather than a height.
/// The frame it publishes is in screen coordinates and says how big the keyboard is, which is not the
/// same question: a window that doesn't fill the screen, which is every iPad window that isn't
/// full-screen, is covered by only the part of the keyboard that reaches into it. Converting the frame
/// into the window and intersecting is the only reading that holds in both cases.
struct KeyboardCover: ViewModifier {
    @Binding
    var covered: CGFloat

    func body(content: Content) -> some View {
        content.background(Probe(report: move))
    }

    private func move(to reach: CGFloat, over settling: Double) {
        guard reach != covered else { return }

        withAnimation(.easeOut(duration: settling)) { covered = reach }
    }

    /// A view of no size, for the window it stands in: the conversion needs one and SwiftUI hands out
    /// no windows.
    private struct Probe: UIViewRepresentable {
        let report: (CGFloat, Double) -> Void

        func makeUIView(context: Context) -> ProbeView { ProbeView(report: report) }

        func updateUIView(_ view: ProbeView, context: Context) { view.report = report }
    }

    final class ProbeView: UIView {
        var report: (CGFloat, Double) -> Void

        init(report: @escaping (CGFloat, Double) -> Void) {
            self.report = report
            super.init(frame: .zero)

            // Every arrival, departure and resize: a keyboard changes depth when its own bar comes and
            // goes, and a height read once is wrong from then on.
            for name in [
                UIResponder.keyboardWillChangeFrameNotification,
                UIResponder.keyboardWillHideNotification,
            ] {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(keyboardMoved),
                    name: name,
                    object: nil
                )
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        @objc private func keyboardMoved(_ note: Notification) {
            guard let window else { return }

            let settling = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double

            guard
                note.name != UIResponder.keyboardWillHideNotification,
                let onScreen = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            else {
                return report(0, settling ?? Self.settling)
            }

            // `from: nil` reads the frame as the screen's, which is how the keyboard publishes it.
            let inWindow = window.convert(onScreen, from: nil)
            let shared = window.bounds.intersection(inWindow)

            report(shared.isNull ? 0 : shared.height, settling ?? Self.settling)
        }

        /// What the keyboard is taken to be settling in when it doesn't say.
        private static let settling: Double = 0.25
    }
}

extension View {
    /// Keeps `covered` at how much of this view's window the keyboard hides.
    func keyboardCover(_ covered: Binding<CGFloat>) -> some View {
        modifier(KeyboardCover(covered: covered))
    }
}
