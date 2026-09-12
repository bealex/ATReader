//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// One book in a catalogue's answer.
public struct OPDSEntry: Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let authors: [String]
    public let summary: String?
    public let language: String?
    /// Every way the catalogue offers to take the book away, in the order it offered them.
    public let acquisitions: [OPDSAcquisition]
    /// Another feed this entry leads to, where it is a section rather than a book.
    ///
    /// A catalogue is a tree: its sections lead to more sections and end in books. An entry with one
    /// of these and nothing to acquire is a branch, and one with something to acquire is a leaf.
    public let navigation: URL?

    public init(
        id: String,
        title: String,
        authors: [String],
        summary: String?,
        language: String?,
        acquisitions: [OPDSAcquisition],
        navigation: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.authors = authors
        self.summary = summary
        self.language = language
        self.acquisitions = acquisitions
        self.navigation = navigation
    }

    /// True where this leads somewhere rather than offering something.
    public var isSection: Bool { acquisitions.isEmpty && navigation != nil }

    public var authorLine: String { authors.joined(separator: ", ") }

    /// The one to take, where the catalogue offers a shape this reader can open.
    ///
    /// A zipped FB2 before a bare one: it is the same book and a fraction of the bytes, and whoever
    /// opens it here unzips either.
    public func preferred(among kinds: [OPDSAcquisition.Kind]) -> OPDSAcquisition? {
        for kind in kinds {
            if let found = acquisitions.first(where: { $0.kind == kind }) { return found }
        }

        return nil
    }
}

/// A way of taking one book away, and what shape it comes in.
public struct OPDSAcquisition: Sendable, Hashable {
    public enum Kind: String, Sendable, CaseIterable {
        case fb2Zip
        case fb2
        case epub
        case other
    }

    public let url: URL
    /// The media type the catalogue gave, kept as it was for anything that wants to look closer.
    public let mediaType: String
    public let kind: Kind

    public init(url: URL, mediaType: String) {
        self.url = url
        self.mediaType = mediaType
        self.kind = Self.kind(of: mediaType, at: url)
    }

    /// What shape a link leads to, read from the media type and then from the address.
    ///
    /// Catalogues disagree about how to spell these, and some send a bare `application/octet-stream`
    /// with the shape only in the path, so both are asked.
    private static func kind(of mediaType: String, at url: URL) -> Kind {
        let type = mediaType.lowercased()
        let path = url.absoluteString.lowercased()

        if type.contains("fb2") || path.contains("fb2") {
            return type.contains("zip") || path.contains("zip") ? .fb2Zip : .fb2
        }

        if type.contains("epub") || path.contains("epub") { return .epub }

        return .other
    }
}

/// A catalogue's answer: the books in it, and where to ask for more.
public struct OPDSFeed: Sendable {
    public let title: String?
    public let entries: [OPDSEntry]
    /// The OpenSearch description this catalogue points at, where it has one.
    public let searchDescription: URL?
    /// A search address the feed gave directly, already carrying its own `{searchTerms}`.
    public let searchTemplate: String?
    /// The next page of this same answer, where the catalogue says there is one.
    public let next: URL?

    public init(
        title: String?,
        entries: [OPDSEntry],
        searchDescription: URL?,
        searchTemplate: String?,
        next: URL? = nil
    ) {
        self.title = title
        self.entries = entries
        self.searchDescription = searchDescription
        self.searchTemplate = searchTemplate
        self.next = next
    }
}

/// One page of an answer: the books on it, and where the page after it is.
///
/// Paging follows the catalogue's own `next` rather than counting pages into the template. A feed
/// that has run out says so by offering none, which is the only reliable way to know.
public struct OPDSPage: Sendable {
    public let entries: [OPDSEntry]
    public let next: URL?

    public init(entries: [OPDSEntry], next: URL?) {
        self.entries = entries
        self.next = next
    }
}

/// What a catalogue's OpenSearch description says about asking it something.
public struct OPDSSearch: Sendable {
    public let template: String
    /// What the catalogue calls its first page. The standard's default is one; some count from nought.
    public let firstPage: Int

    public init(template: String, firstPage: Int) {
        self.template = template
        self.firstPage = firstPage
    }
}
