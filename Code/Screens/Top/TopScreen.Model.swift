//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import Foundation

extension TopScreen {
    @Observable @MainActor
    final class Model {
        /// The orderings that read as a chart; the catalogue's other sorts are offered in search instead.
        static let chartOrders: [CatalogSorting] = [ .popular, .trending, .likes, .views ]

        var sorting: CatalogSorting = .popular {
            didSet { reload(ifChanged: oldValue != sorting) }
        }

        var period: RatingPeriod = .week {
            didSet { reload(ifChanged: oldValue != period) }
        }

        var genreId: Int? {
            didSet { reload(ifChanged: oldValue != genreId) }
        }

        let feed: CatalogFeed

        private(set) var genres: [Genre] = []

        @ObservationIgnored
        private let session: SessionStore

        @ObservationIgnored
        private var hasLoaded = false

        init(session: SessionStore) {
            self.session = session
            self.feed = CatalogFeed(client: session.client)
        }

        func loadIfNeeded() async {
            guard !hasLoaded else { return }

            hasLoaded = true
            async let chart: Void = reload()
            async let catalogue: Void = loadGenres()
            _ = await (chart, catalogue)
        }

        func reload() async {
            await feed.load(CatalogQuery(
                page: 1,
                pageSize: 30,
                sorting: sorting,
                genreId: genreId,
                ratingPeriod: period.rawValue
            ))
        }

        private func loadGenres() async {
            guard let loaded = try? await session.client.genres() else { return }

            genres =
                loaded
                .filter(\.isTopLevel)
                .sorted { ($0.workCount ?? 0) > ($1.workCount ?? 0) }
        }

        /// Filter changes reload the chart, but only once the first load has settled.
        private func reload(ifChanged changed: Bool) {
            guard changed, hasLoaded else { return }

            Task { await reload() }
        }
    }
}
