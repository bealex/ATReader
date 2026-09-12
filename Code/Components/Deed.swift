//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import UIKit

/// One thing that can be done to a book, a series or an author.
///
/// A value rather than a menu, because the same list is set out twice: as a SwiftUI menu on a row, and
/// as a UIKit one on a book the shelf drew itself. Written out twice it would drift, and the reader
/// would find a different menu depending on which of the two they pressed.
enum Deed: Identifiable {
    case act(Act)
    /// A menu of its own, named, holding further deeds.
    case menu(String, [Deed])

    struct Act {
        let title: String
        let systemImage: String
        var isDestructive = false
        var isEnabled = true
        /// Ticked, for a menu where one of several is the one in force.
        var isOn = false
        let run: @MainActor @Sendable () -> Void
    }

    var id: String {
        switch self {
            case let .act(act): act.title
            case let .menu(title, _): title
        }
    }

    static func act(
        _ title: String,
        systemImage: String,
        isDestructive: Bool = false,
        isEnabled: Bool = true,
        isOn: Bool = false,
        run: @escaping @MainActor @Sendable () -> Void
    ) -> Deed {
        .act(Act(
            title: title,
            systemImage: systemImage,
            isDestructive: isDestructive,
            isEnabled: isEnabled,
            isOn: isOn,
            run: run
        ))
    }
}

extension [Deed] {
    /// The list as UIKit sets it out.
    var menu: UIMenu { UIMenu(children: map(\.element)) }

    /// Nothing to press is no menu at all, rather than an empty one nothing can be done in.
    var offered: UIMenu? { isEmpty ? nil : menu }

    /// The list under a heading saying what it acts on, which a context menu stands above it and
    /// nobody can press.
    func offered(under title: String, and subtitle: String? = nil) -> UIMenu? {
        guard !isEmpty else { return nil }

        return UIMenu(title: title, subtitle: subtitle, children: map(\.element))
    }
}

private extension Deed {
    var element: UIMenuElement {
        switch self {
            case let .act(act):
                var attributes: UIMenuElement.Attributes = act.isDestructive ? .destructive : []

                if !act.isEnabled { attributes.insert(.disabled) }

                return UIAction(
                    title: act.title,
                    image: UIImage(systemName: act.systemImage),
                    attributes: attributes,
                    state: act.isOn ? .on : .off
                ) { _ in act.run() }
            case let .menu(title, deeds):
                return UIMenu(title: title, children: deeds.map(\.element))
        }
    }
}

/// The list as SwiftUI sets it out.
struct DeedMenu: View {
    let deeds: [Deed]

    var body: some View {
        ForEach(deeds) { deed in
            switch deed {
                case let .act(act):
                    Button(role: act.isDestructive ? .destructive : nil, action: act.run) {
                        Label(act.title, systemImage: act.systemImage)
                    }
                    .disabled(!act.isEnabled)
                case let .menu(title, held):
                    Menu(title) { DeedMenu(deeds: held) }
            }
        }
    }
}
