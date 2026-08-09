//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import Testing

@testable import AuthorToday

/// The service returns two different shapes for `coverUrl`, and getting this wrong is silent: a
/// schemeless URL is accepted by `URL(string:)` and then rejected by `URLSession` at load time.
/// Paths below are made up.
struct CoverURLTests {
    @Test
    func passesAbsoluteURLsThrough() {
        let raw = "https://cm.author.today/content/2020/01/02/abc.jpg?width=265&height=400&rmode=max"

        #expect(CoverURL.absolute(raw)?.absoluteString == raw)
    }

    @Test
    func makesTheCatalogueRelativePathAbsolute() throws {
        let url = try #require(CoverURL.absolute("2020/01/02/abc.jpg"))

        #expect(url.scheme == "https", "a schemeless URL is what URLSession rejects")
        #expect(url.host == "cm.author.today")
        #expect(url.path == "/content/2020/01/02/abc.jpg")
    }

    /// Asking the CDN to resize is what turns a ~450 KB original into ~50 KB.
    @Test
    func asksTheServiceToResizeARelativePath() throws {
        let url = try #require(CoverURL.absolute("2020/01/02/abc.jpg"))
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(query.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })

        #expect(values["width"] == String(CoverURL.requestedWidth))
        #expect(values["height"] == String(CoverURL.requestedWidth * 3 / 2))
        #expect(values["rmode"] == "max")
    }

    @Test
    func rejectsEmptyAndMissingValues() {
        #expect(CoverURL.absolute(nil) == nil)
        #expect(CoverURL.absolute("") == nil)
    }
}
