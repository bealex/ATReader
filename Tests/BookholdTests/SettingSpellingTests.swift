//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Testing

@testable import Bookhold

/// The names the reader's type settings are written down under, which a build that spelled one
/// differently would read back as a setting it had never heard of.
struct SettingSpellingTests {
    @Test
    func keepsTheSpellingsThatAreWrittenDown() {
        #expect(ReaderSettings.Face.allCases.map(\.rawValue) == [
            "serif", "system", "rounded", "georgia", "palatino",
            "charter", "stix", "baskerville", "hoefler", "avenir",
        ])
        #expect(ReaderSettings.Weight.allCases.map(\.rawValue) == [ "light", "regular", "medium", "semibold" ])
    }
}
