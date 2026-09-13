//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookRenderer
import SwiftUI
import Testing
import UIKit

@testable import Bookhold

/// What a book's stored measurements are filed against.
///
/// Every chapter's placement is kept against this string. Change what goes into it, or the spelling of
/// a face or a weight, and every book on every device silently measures itself again on next open. The
/// only symptom is a slow first page, which nobody reports, so it is pinned here instead.
struct PageContextFingerprintTests {
    private static var style: ChapterTextStyle {
        ChapterTextStyle(
            face: .serif,
            weight: .regular,
            fontSize: 19,
            lineSpacing: 7,
            letterSpacing: 0,
            justifiesRussian: true,
            justifiesEnglish: false,
            textColor: .label
        )
    }

    private static var context: ChapterLayout.Context {
        ChapterLayout.Context(
            style: style,
            margins: 24,
            pageSize: CGSize(width: 390, height: 844),
            safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        )
    }

    @Test
    func isTheStringEveryStoredMeasurementIsFiledAgainst() {
        #expect(
            Self.context.fingerprint
                == "18|serif|regular|19.0|7.0|0.0|true|false|24.0|390.0x844.0|59.0,0.0,34.0,0.0"
        )
    }

    /// The two the reader picks, spelled as they are persisted and as they are filed under.
    @Test
    func keepsTheSpellingsThatAreWrittenDown() {
        #expect(ReaderSettings.Face.allCases.map(\.rawValue) == [
            "serif", "system", "rounded", "georgia", "palatino",
            "charter", "stix", "baskerville", "hoefler", "avenir",
        ])
        #expect(ReaderSettings.Weight.allCases.map(\.rawValue) == [ "light", "regular", "medium", "semibold" ])
    }
}
