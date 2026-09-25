//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import Testing

@testable import AuthorToday

/// Reading the website's search page, which stands in for the free-text search the API doesn't have.
///
/// The pages here are made up in the site's shape; no title or name in them is real.
struct SiteSearchTests {
    private static func page(found: String?, ids: [Int], pages: [Int] = [], empty: Bool = false) -> String {
        let hits = ids.map {
            """
            <a data-pjax href="/work/\($0)" class="work-row item-link item-content">
            <div class="item-title">Zorblat \($0)</div></a>
            <a href="/work/\($0)/read">read</a>
            """
        }
        let links = pages.map { #"<a href="/search?category=works&amp;q=zorb&amp;page=\#($0)">\#($0)</a>"# }

        return [
            #"<a href="/work/genre/all?sorting=popular">menu</a>"#,
            found.map { #"<div class="mb">Найдено: \#($0)</div>"# } ?? "",
            empty ? "<p>Ваш запрос не дал результатов. Попробуйте поменять параметры поиска.</p>" : "",
        ]
        .joined(separator: "\n") + hits.joined(separator: "\n") + links.joined(separator: "\n")
    }

    @Test
    func hitsAreReadInTheSitesOrder() throws {
        let results = try SiteSearchResults(html: Self.page(found: "3", ids: [ 31, 7, 19 ]), page: 1)

        #expect(results.ids == [ 31, 7, 19 ])
        #expect(results.total == 3)
        #expect(results.isLastPage)
    }

    /// A link to a work that isn't a result row, like a genre or a reading link, is no hit.
    @Test
    func onlyResultRowsCount() throws {
        let html = Self.page(found: "1", ids: [ 5 ]) + #"<a href="/work/99" class="author-link">other</a>"#
        let results = try SiteSearchResults(html: html, page: 1)

        #expect(results.ids == [ 5 ])
    }

    @Test
    func theClassMayComeBeforeTheLink() throws {
        let html = #"<div class="mb">Найдено: 1</div><a class="work-row" data-pjax href="/work/42">x</a>"#

        #expect(try SiteSearchResults(html: html, page: 1).ids == [ 42 ])
    }

    @Test
    func aLaterPageIsNotTheLast() throws {
        let first = try SiteSearchResults(html: Self.page(found: "1 876", ids: [ 1, 2 ], pages: [ 2, 63 ]), page: 1)
        let last = try SiteSearchResults(html: Self.page(found: "1876", ids: [ 3 ], pages: [ 1, 62 ]), page: 63)

        #expect(first.total == 1876)
        #expect(!first.isLastPage)
        #expect(last.isLastPage)
    }

    @Test
    func noResultsIsAnEmptyPage() throws {
        let results = try SiteSearchResults(html: Self.page(found: nil, ids: [], empty: true), page: 1)

        #expect(results.ids.isEmpty)
        #expect(results.total == 0)
        #expect(results.isLastPage)
    }

    /// A page with neither hits nor the site's "no results" is the guard's challenge, which must not
    /// read as nothing found.
    @Test
    func aPageThatIsntASearchIsAnError() {
        #expect(throws: AuthorTodayError.self) {
            try SiteSearchResults(html: "<html><body>Checking your browser</body></html>", page: 1)
        }
    }

    /// The API ignores a term, so it's never sent there.
    @Test
    func theCatalogueIsNeverAskedForText() {
        let names = CatalogQuery(text: "zorb").queryItems.map(\.name)

        #expect(!names.contains("q"))
    }
}
