//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// The one path every screen pushes onto.
///
/// The stack wraps the tabs rather than sitting inside each of them, so the tab bar is content of the
/// stack's first screen and a push covers it the way it covers everything else. That is what carries
/// the bar off with the screen it belongs to instead of switching it off underneath. The cost is that
/// there is one path for the app rather than one per tab.
@Observable
@MainActor
final class Navigator {
    var path: [AppRoute] = []
}
