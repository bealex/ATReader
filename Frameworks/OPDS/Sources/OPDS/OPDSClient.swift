//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// Reads an OPDS catalogue: what it offers to search with, what a search answers, and the file behind
/// an answer.
///
/// OPDS is Atom, so everything here is XML parsing and nothing else. The catalogue's address is the
/// reader's to give, since every library has its own.
public actor OPDSClient {
    public enum Failure: Error, Sendable {
        /// The address given is not one this can ask anything of.
        case badAddress
        /// The catalogue answered, but not with a feed.
        case notAFeed
        /// The catalogue offers no way to search.
        case noSearch
        case http(Int)
    }

    private let root: URL
    private let session: URLSession
    /// How the catalogue is searched, once it has been asked. Asking is a fetch of its own, so it
    /// happens once.
    private var search: OPDSSearch?

    public init(root: URL, session: URLSession = .shared) {
        self.root = root
        self.session = session
    }

    /// The first page of what a catalogue answers a query with.
    public func search(_ query: String) async throws -> OPDSPage {
        let search = try await searchTemplate()

        guard
            let url = Self.address(from: search.template, query: query, page: search.firstPage, against: root)
        else { throw Failure.badAddress }

        return try await page(at: url)
    }

    /// The page after one already read, which the catalogue itself said where to find.
    public func more(after url: URL) async throws -> OPDSPage {
        try await page(at: url)
    }

    /// Whatever stands at one address: the sections of a catalogue, or the books at the end of them.
    ///
    /// A catalogue is a tree and this walks it. Where a section holds exactly one thing and that thing
    /// is another section, it is followed at once: an index that has narrowed to a single answer is
    /// asking to be stepped through rather than tapped through.
    public func browse(_ url: URL) async throws -> OPDSPage {
        var page = try await self.page(at: url)
        var followed = 0

        while page.entries.count == 1, let only = page.entries.first, only.isSection,
                let next = only.navigation, followed < Self.mostToFollow {
            page = try await self.page(at: next)
            followed += 1
        }

        return page
    }

    /// The sections a catalogue offers at its root: by author, by series, whatever it keeps.
    public func sections() async throws -> [OPDSEntry] {
        try await feed(at: root).entries
    }

    /// How far a run of single answers is followed before it is left to the reader. A catalogue whose
    /// every index holds one entry would otherwise be walked to its end in one tap.
    private static let mostToFollow = 8

    private func page(at url: URL) async throws -> OPDSPage {
        let feed = try await feed(at: url)

        return OPDSPage(entries: feed.entries, next: feed.next)
    }

    /// The bytes behind one acquisition link.
    public func download(_ acquisition: OPDSAcquisition) async throws -> Data {
        try await bytes(at: acquisition.url)
    }

    /// Where this catalogue wants a query put.
    ///
    /// The description first. It is the standard's own way of saying where a query goes, it can carry
    /// several addresses and say what each answers in, and a catalogue offering both has been seen to
    /// advertise an inline link its own server then answers with an error. The inline one is the
    /// fallback, for a catalogue that publishes no description at all.
    private func searchTemplate() async throws -> OPDSSearch {
        if let search { return search }

        let feed = try await self.feed(at: root)

        if let description = feed.searchDescription,
                let data = try? await bytes(at: description),
                let found = OPDSParser.search(in: data) {
            search = found
            return found
        }

        guard let direct = feed.searchTemplate, direct.contains("{searchTerms}") else { throw Failure.noSearch }

        let found = OPDSSearch(template: direct, firstPage: 1)

        search = found
        return found
    }

    /// A template with the query put into it, resolved against the catalogue's own address.
    static func address(from template: String, query: String, page: Int? = nil, against root: URL) -> URL? {
        let escaped = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
        var filled = template.replacingOccurrences(of: "{searchTerms}", with: escaped)

        // The page wanted is filled in rather than left out, so an answer can be walked through from
        // its first page as well as by following the catalogue's own `next`.
        if let page {
            for name in [ "{startPage}", "{startPage?}" ] {
                filled = filled.replacingOccurrences(of: name, with: String(page))
            }
        }

        return URL(string: withoutUnfilled(filled), relativeTo: root)?.absoluteURL
    }

    /// Every parameter nothing filled in, taken out pair and all.
    ///
    /// A template carries more than the query: how many to a page, what to answer in, where to start.
    /// The standard says an optional one nobody fills is left out, and leaving the name behind with an
    /// empty value is not leaving it out — a catalogue reading `pageNumber=` as a page number answers
    /// nothing at all.
    static func withoutUnfilled(_ address: String) -> String {
        let bare = { (part: Substring) in
            part.replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
        }

        guard let mark = address.firstIndex(of: "?") else { return bare(address[...]) }

        let base = bare(address[..<mark])
        let kept = address[address.index(after: mark)...]
            .split(separator: "&")
            .filter { !$0.contains("{") }

        return kept.isEmpty ? base : base + "?" + kept.joined(separator: "&")
    }

    private func feed(at url: URL) async throws -> OPDSFeed {
        let data = try await bytes(at: url)

        guard let feed = OPDSParser.feed(in: data, from: url) else { throw Failure.notAFeed }

        return feed
    }

    private func bytes(at url: URL) async throws -> Data {
        var request = URLRequest(url: url)

        request.setValue("application/atom+xml, application/xml;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            throw Failure.http(http.statusCode)
        }

        return data
    }
}
