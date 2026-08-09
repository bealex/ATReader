//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

extension AuthorTodayClient {
    /// Searches the catalogue.
    ///
    /// The free-text term matches both titles and author names, so one query serves both kinds of search.
    /// Leaving ``CatalogQuery/text`` empty turns the same call into a ranked list — that is how the "top"
    /// lists are built, by varying ``CatalogQuery/sorting`` and ``CatalogQuery/ratingPeriod``.
    public func search(_ query: CatalogQuery) async throws -> CatalogPage {
        try await send(Endpoint(path: "/v1/catalog/search", query: query.queryItems))
    }

    public func genres() async throws -> [Genre] {
        try await send(Endpoint(path: "/v1/work/genres"))
    }
}
