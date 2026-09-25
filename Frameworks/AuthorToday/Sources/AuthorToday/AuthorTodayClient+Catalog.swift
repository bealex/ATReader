//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

extension AuthorTodayClient {
    /// Searches the catalogue.
    ///
    /// A ``CatalogQuery/text`` term matches titles and author names together, and only ``CatalogQuery/page``
    /// and ``CatalogQuery/sorting`` (popular, recent or trending) apply to it; the service decides the page
    /// size. With no term the call is a ranked list, which is how the "top" lists are built, by varying
    /// ``CatalogQuery/sorting`` and ``CatalogQuery/ratingPeriod``.
    public func search(_ query: CatalogQuery) async throws -> CatalogPage {
        if let text = query.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return try await searchSite(text, page: query.page, sorting: query.sorting)
        }

        return try await send(Endpoint(path: "/v1/catalog/search", query: query.queryItems))
    }

    public func genres() async throws -> [Genre] {
        try await send(Endpoint(path: "/v1/work/genres"))
    }
}
