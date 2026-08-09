//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import Foundation

/// Paged access to `/v1/catalog/search`, shared by the search and top-list screens.
///
/// Both screens ask the same endpoint the same way; only the query differs — a free-text term for search,
/// a sorting and rating window for the charts.
@Observable @MainActor
final class CatalogFeed {
    private(set) var works: [WorkSummary] = []
    private(set) var totalCount: Int?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    private(set) var hasLoaded = false

    @ObservationIgnored
    private var query = CatalogQuery()

    @ObservationIgnored
    private var reachedEnd = false

    @ObservationIgnored
    private var seenIds: Set<Int> = []

    @ObservationIgnored
    private let client: AuthorTodayClient

    init(client: AuthorTodayClient) {
        self.client = client
    }

    var isEmpty: Bool { works.isEmpty && !isLoading }

    /// Replaces the query and reloads from the first page.
    func load(_ query: CatalogQuery) async {
        var query = query
        query.page = 1
        self.query = query
        reachedEnd = false
        await fetch(replacing: true)
    }

    /// Called as the list nears its end; a no-op once the service reports the last page.
    func loadMoreIfNeeded(currentItem: WorkSummary) async {
        guard !reachedEnd, !isLoading, !isLoadingMore else { return }
        guard works.suffix(5).contains(where: { $0.id == currentItem.id }) else { return }

        query.page += 1
        await fetch(replacing: false)
    }

    private func fetch(replacing: Bool) async {
        if replacing {
            isLoading = true
        } else {
            isLoadingMore = true
        }

        errorMessage = nil

        do {
            let page = try await client.search(query)
            let incoming = page.works.map(WorkSummary.init)

            if replacing {
                seenIds = Set(incoming.map(\.id))
                works = incoming
            } else {
                let fresh = incoming.filter { seenIds.insert($0.id).inserted }
                works.append(contentsOf: fresh)
            }

            totalCount = page.realTotalCount
            reachedEnd = page.isLastPage == true || incoming.isEmpty
            hasLoaded = true
        } catch let error as AuthorTodayError {
            errorMessage = error.localizedDescription
            if !replacing { query.page -= 1 }
        } catch {
            errorMessage = "Couldn’t load the list."
            if !replacing { query.page -= 1 }
        }

        isLoading = false
        isLoadingMore = false
    }
}
