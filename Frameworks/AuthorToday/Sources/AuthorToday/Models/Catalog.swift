//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// One page of `/v1/catalog/search`.
public struct CatalogPage: Decodable, Sendable {
    public let searchResults: [CatalogWork]?
    public let realTotalCount: Int?
    public let isLastPage: Bool?
    public let errorMessage: String?

    public var works: [CatalogWork] { searchResults ?? [] }
}

/// A work as the catalogue presents it — richer than a library entry (blurb, tags, view counts).
public struct CatalogWork: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let title: String
    public let annotation: String?
    public let coverUrl: String?

    public let authorId: Int?
    public let authorFIO: String?
    public let authorUserName: String?
    public let coAuthorFIO: String?

    public let seriesId: Int?
    public let seriesTitle: String?

    public let tags: [String]?
    public let genreId: Int?

    public let textLength: Int?
    public let likeCount: Int?
    public let viewCount: Int?
    public let commentCount: Int?

    public let price: Double?
    public let discount: Double?
    public let isPurchased: Bool?
    public let status: WorkStatus?
    public let formEnum: WorkForm?
    public let format: WorkFormat?
    public let adultOnly: Bool?
    public let isFinished: Bool?
    public let lastModificationTime: Date?
    public let workInLibraryState: LibraryState?

    public var coverURL: URL? { CoverURL.absolute(coverUrl) }

    public var authorLine: String {
        let names = [ authorFIO, coAuthorFIO ].compactMap { $0 }.filter { !$0.isEmpty }
        return names.isEmpty ? String(localized: "Unknown author", bundle: .module) : names.joined(separator: ", ")
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// The knobs ``AuthorTodayClient/search(_:)`` exposes over `/v1/catalog/search`.
public struct CatalogQuery: Sendable, Equatable {
    public var text: String?
    public var page: Int
    public var pageSize: Int
    public var sorting: CatalogSorting
    public var genreId: Int?
    /// Restricts the ranking window for the "top" lists, e.g. `month` or `year`.
    public var ratingPeriod: String?
    public var onlyFree: Bool
    public var onlyFinished: Bool

    public init(
        text: String? = nil,
        page: Int = 1,
        pageSize: Int = 30,
        sorting: CatalogSorting = .popular,
        genreId: Int? = nil,
        ratingPeriod: String? = nil,
        onlyFree: Bool = false,
        onlyFinished: Bool = false
    ) {
        self.text = text
        self.page = page
        self.pageSize = pageSize
        self.sorting = sorting
        self.genreId = genreId
        self.ratingPeriod = ratingPeriod
        self.onlyFree = onlyFree
        self.onlyFinished = onlyFinished
    }

    var queryItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "ps", value: String(pageSize)),
            URLQueryItem(name: "sorting", value: sorting.rawValue),
        ]

        if let text, !text.isEmpty { items.append(URLQueryItem(name: "q", value: text)) }
        if let genreId { items.append(URLQueryItem(name: "genreId", value: String(genreId))) }
        if let ratingPeriod { items.append(URLQueryItem(name: "rp", value: ratingPeriod)) }
        if onlyFree { items.append(URLQueryItem(name: "access", value: "free")) }
        if onlyFinished { items.append(URLQueryItem(name: "state", value: "finished")) }

        return items
    }
}
