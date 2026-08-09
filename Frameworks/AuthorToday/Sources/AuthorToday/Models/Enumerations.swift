//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// Where a work sits in the reader's own library.
public enum LibraryState: String, DefaultingDecodable, CaseIterable, Hashable {
    case none = "None"
    case reading = "Reading"
    case saved = "Saved"
    case finished = "Finished"
    case disliked = "Disliked"

    public static let fallback: Self = .none

    /// The shelves worth offering as a filter — `none` means "not in the library at all".
    public static let shelves: [Self] = [ .reading, .saved, .finished ]

    public var title: String {
        switch self {
            case .none: String(localized: "Not in library", bundle: .module)
            case .reading: String(localized: "Reading", bundle: .module)
            case .saved: String(localized: "Saved", bundle: .module)
            case .finished: String(localized: "Finished", bundle: .module)
            case .disliked: String(localized: "Disliked", bundle: .module)
        }
    }

    public var systemImage: String {
        switch self {
            case .none: "books.vertical"
            case .reading: "book"
            case .saved: "bookmark"
            case .finished: "checkmark.circle"
            case .disliked: "hand.thumbsdown"
        }
    }
}

/// How a work is paid for.
public enum WorkStatus: String, DefaultingDecodable, Hashable {
    case free = "Free"
    case subscription = "Subscription"
    case sales = "Sales"
    case suspended = "Suspended"

    public static let fallback: Self = .free
}

/// The literary form the author filed the work under.
public enum WorkForm: String, DefaultingDecodable, Hashable {
    case any = "Any"
    case story = "Story"
    case novel = "Novel"
    case storyBook = "StoryBook"
    case poetry = "Poetry"
    case translation = "Translation"
    case tale = "Tale"

    public static let fallback: Self = .any

    public var title: String {
        switch self {
            case .any: String(localized: "Any form", bundle: .module)
            case .story: String(localized: "Short story", bundle: .module)
            case .novel: String(localized: "Novel", bundle: .module)
            case .storyBook: String(localized: "Collection", bundle: .module)
            case .poetry: String(localized: "Poetry", bundle: .module)
            case .translation: String(localized: "Translation", bundle: .module)
            case .tale: String(localized: "Novella", bundle: .module)
        }
    }
}

/// Text or audio.
public enum WorkFormat: String, DefaultingDecodable, Hashable {
    case any = "Any"
    case eBook = "EBook"
    case audiobook = "Audiobook"

    public static let fallback: Self = .any
}

/// The orderings the catalogue offers, mirroring `/v1/catalog/sort-orders`.
public enum CatalogSorting: String, Sendable, CaseIterable, Hashable {
    case popular
    case trending
    case recent
    case likes
    case views
    case comments
    case length

    public var title: String {
        switch self {
            case .popular: String(localized: "Most popular", bundle: .module)
            case .trending: String(localized: "Trending", bundle: .module)
            case .recent: String(localized: "Newest", bundle: .module)
            case .likes: String(localized: "Most liked", bundle: .module)
            case .views: String(localized: "Most viewed", bundle: .module)
            case .comments: String(localized: "Most discussed", bundle: .module)
            case .length: String(localized: "Longest", bundle: .module)
        }
    }
}

/// Which two-factor challenge the account is enrolled in.
public enum TwoFactorType: String, DefaultingDecodable, Hashable {
    case email = "Email"
    case code = "Code"

    public static let fallback: Self = .code

    public var prompt: String {
        switch self {
            case .email: String(localized: "We emailed you a verification code.", bundle: .module)
            case .code: String(localized: "Enter the code from your authenticator app.", bundle: .module)
        }
    }
}
