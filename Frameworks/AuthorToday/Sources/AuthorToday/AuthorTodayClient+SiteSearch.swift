//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

extension AuthorTodayClient {
    /// Fetches works by id, in the order the ids were given; an id the service doesn't know is left out.
    public func works(ids: [Int]) async throws -> [CatalogWork] {
        guard !ids.isEmpty else { return [] }

        let query = ids.map { URLQueryItem(name: "ids", value: String($0)) }
        let found: [CatalogWork] = try await send(Endpoint(path: "/v1/work/tile-views", query: query))
        let byId = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return ids.compactMap { byId[$0] }
    }

    /// Matches a term against the catalogue through the website's search page, since the API has no
    /// free-text search, then reads the works it names through the API.
    func searchSite(_ text: String, page: Int, sorting: CatalogSorting) async throws -> CatalogPage {
        var items = [
            URLQueryItem(name: "category", value: "works"),
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "page", value: String(page)),
        ]

        if CatalogSorting.searchable.contains(sorting) {
            items.append(URLQueryItem(name: "sorting", value: sorting.rawValue))
        }

        let html = try await fetchSitePage(path: "/search", query: items)
        let results = try SiteSearchResults(html: html, page: page)
        let works = try await works(ids: results.ids)

        return CatalogPage(searchResults: works, realTotalCount: results.total, isLastPage: results.isLastPage)
    }
}

/// What one page of the website's works search names: the works' ids in the site's order, the total and
/// whether another page follows.
struct SiteSearchResults: Equatable {
    let ids: [Int]
    let total: Int
    let isLastPage: Bool

    /// Reads a search page, and throws on a page that is neither a list of hits nor the site's "no
    /// results", which is what a challenge from the guard in front of the site looks like.
    init(html: String, page: Int) throws {
        let ids = Self.captures(of: Self.hit, in: html).compactMap(Int.init)
        let total = Self.captures(of: Self.found, in: html).first.flatMap { Int($0.filter(\.isNumber)) }

        guard
            total != nil || html.contains(Self.noResults)
        else { throw AuthorTodayError.decoding("the search page carried no results") }

        let lastPage = Self.captures(of: Self.pageLink, in: html).compactMap(Int.init).max() ?? page

        var seen: Set<Int> = []

        self.ids = ids.filter { seen.insert($0).inserted }
        self.total = total ?? 0
        self.isLastPage = ids.isEmpty || page >= lastPage
    }

    private static func captures(of pattern: NSRegularExpression, in text: String) -> [String] {
        pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    /// A hit is a link to the work whose class names it a `work-row`, whichever order the two come in.
    private static let hit = regex(#"<a\s(?=[^>]*\bclass="[^"]*\bwork-row\b)[^>]*\bhref="/work/(\d+)""#)
    private static let found = regex(#"Найдено:\s*([\d\s]+?)\s*<"#)
    private static let pageLink = regex(#"href="/search\?[^"]*\bpage=(\d+)"#)
    private static let noResults = "не дал результатов"

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }
}

extension CatalogPage {
    init(searchResults: [CatalogWork], realTotalCount: Int?, isLastPage: Bool) {
        self.searchResults = searchResults
        self.realTotalCount = realTotalCount
        self.isLastPage = isLastPage
        self.errorMessage = nil
    }
}
