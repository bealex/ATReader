//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import XCTest

/// Finding the tabs, wherever the bar puts them.
///
/// A phone stands its tabs in a bar along the foot of the screen. A screen with room to spare stands
/// them in a pill at the top, which is not a tab bar as far as a test is concerned, so the button has
/// to be looked for in the app itself.
extension XCUIApplication {
    /// One tab, by the name on it.
    ///
    /// A pill at the top offers the name more than once, the tab itself and what stands inside it, so
    /// the first match is taken rather than the query being asked to resolve to a single element.
    func tab(_ name: String) -> XCUIElement {
        let inABar = tabBars.buttons[name]

        return inABar.exists ? inABar : buttons[name].firstMatch
    }

    /// Whether the tabs are on screen at all, which a pushed screen takes them off.
    func showsTabs(named name: String) -> Bool {
        tabBars.firstMatch.exists || buttons[name].exists
    }

    /// Waits for the tabs to arrive, which is how a test knows it has reached the top level.
    func waitForTabs(named name: String, timeout: TimeInterval = 30) -> Bool {
        tab(name).waitForExistence(timeout: timeout) || tabBars.firstMatch.waitForExistence(timeout: 1)
    }
}
