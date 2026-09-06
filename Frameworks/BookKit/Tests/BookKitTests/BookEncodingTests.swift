//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import Testing

@testable import BookKit

/// What a stored book is written as.
///
/// Books are kept as JSON in a column, so these names and raw values are a storage format rather than
/// an implementation detail: rename a property here and every device silently fails to read back the
/// library it already has. The fixtures are generated nonsense.
struct BookEncodingTests {
    @Test
    func encodesEveryFieldUnderTheNameTheStoreHolds() throws {
        let book = Book(
            id: 7,
            title: "Alpha",
            authorLine: "Bravo",
            coverURL: URL(string: "https://example.invalid/c.jpg"),
            annotation: "Charlie",
            seriesTitle: "Delta",
            seriesOrder: 2,
            textLength: 1234,
            likeCount: 56,
            isFinished: true,
            status: .sales,
            isPurchased: false,
            adultOnly: false,
            lastUpdateTime: Date(timeIntervalSince1970: 1),
            readingProgress: 0.5,
            hasStartedReading: true,
            lastReadTime: Date(timeIntervalSince1970: 2),
            lastChapterId: 9,
            libraryState: .reading
        )

        let data = try JSONEncoder().encode(book)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(
            Set(json.keys) == [
                "id", "title", "authorLine", "coverURL", "annotation", "seriesTitle", "seriesOrder",
                "textLength", "likeCount", "isFinished", "status", "isPurchased", "adultOnly",
                "lastUpdateTime", "readingProgress", "hasStartedReading", "lastReadTime",
                "lastChapterId", "libraryState",
            ]
        )
        #expect(json["status"] as? String == "Sales")
        #expect(json["libraryState"] as? String == "Reading")
    }

    /// The service's own spellings, which is what makes the mapping total and the stored rows readable.
    @Test
    func keepsTheRawValuesTheServiceUses() {
        #expect(BookShelf.allCases.map(\.rawValue) == [ "None", "Reading", "Saved", "Finished", "Disliked" ])
        #expect(BookPricing.free.rawValue == "Free")
        #expect(BookPricing.subscription.rawValue == "Subscription")
        #expect(BookPricing.sales.rawValue == "Sales")
        #expect(BookPricing.suspended.rawValue == "Suspended")
    }

    @Test
    func numbersBooksFromFilesBelowZeroAndTheirChaptersInsideTheirOwnBlock() {
        let first = BookNumbering.workId(sequence: 1)

        #expect(BookNumbering.isLocal(first))
        #expect(!BookNumbering.isLocal(7))
        #expect(BookNumbering.sequence(workId: first) == 1)
        #expect(BookNumbering.chapterId(workId: first, index: 0) == first - 1)
        // A chapter of book one can never collide with book two's own id.
        #expect(BookNumbering.chapterId(workId: first, index: 5) > BookNumbering.workId(sequence: 2))
    }
}
