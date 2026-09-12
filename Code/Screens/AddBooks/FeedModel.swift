//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import OPDS
import SwiftUI

/// What is being looked for, which decides where the looking starts.
enum CatalogueScope: String, CaseIterable, Identifiable {
    case books
    case authors
    case series

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
            case .books: "Books"
            case .authors: "Authors"
            case .series: "Series"
        }
    }

    /// What a query means here: a book is searched for by any part of its name, an author or a series
    /// by what its name begins with, since that is what a catalogue's indexes are cut by.
    var prompt: LocalizedStringKey {
        switch self {
            case .books: "Title or author"
            case .authors, .series: "First letters"
        }
    }

    /// What the section for this is called in a catalogue's own addresses, in the spellings catalogues
    /// use. A catalogue names its sections in its own language, so the address is what is read.
    var marks: [String] {
        switch self {
            case .books: []
            case .authors: [ "author" ]
            case .series: [ "series", "sequence" ]
        }
    }
}

/// One feed of a catalogue, however it was arrived at: searched for, browsed into, or paged on from.
@Observable @MainActor
final class FeedModel {
    private(set) var entries: [OPDSEntry] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasLoaded = false
    private(set) var message: String?
    /// The book being fetched, so its row can say so and no two are fetched at once.
    private(set) var fetching: OPDSEntry.ID?
    private(set) var next: URL?

    /// Whoever reads a downloaded file into the library. Given by the view, which has the environment.
    var inbox: BookInbox?

    /// What this reader can open, best first. A zipped FB2 is the same book as a bare one and a
    /// fraction of the bytes.
    static let wanted: [OPDSAcquisition.Kind] = [ .fb2Zip, .fb2 ]

    private var client: OPDSClient?
    private var address: String?

    /// Whatever stands at one address.
    func open(_ url: URL, at address: String) async {
        guard let client = client(for: address) else { return }

        await load { try await client.browse(url) }
    }

    /// The books a catalogue answers a query with.
    func search(_ query: String, at address: String) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty, let client = client(for: address) else { return }

        await load { try await client.search(query) }
    }

    /// The index of authors or series, narrowed to what a name begins with.
    ///
    /// The section itself is the catalogue's own, found among the ones it offers at its root. Narrowing
    /// by putting the prefix on the end of that address is a convention rather than anything the
    /// standard says, so a catalogue that makes nothing of it is simply opened at the section instead
    /// and browsed down by hand.
    func open(_ scope: CatalogueScope, beginning prefix: String, at address: String) async {
        let prefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let client = client(for: address) else { return }

        await load {
            let sections = try await client.sections()

            guard
                let section = sections.first(where: { entry in
                    guard let path = entry.navigation?.path.lowercased() else { return false }

                    return scope.marks.contains { path.contains($0) }
                }),
                let url = section.navigation
            else { throw Failure.noSection }
            guard !prefix.isEmpty else { return try await client.browse(url) }

            let narrowed = url.appendingPathComponent(prefix)

            // Tried, and given up on quietly: the section itself is always there to browse.
            if let found = try? await client.browse(narrowed), !found.entries.isEmpty { return found }

            return try await client.browse(url)
        }
    }

    /// The next page of the same feed, put after what is already showing.
    func loadMore() async {
        guard let client, let url = next, !isLoadingMore else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page = try await client.more(after: url)
            let known = Set(entries.map(\.id))

            entries += page.entries.filter { !known.contains($0.id) }
            next = page.next
        } catch {
            message = Self.wording(of: error)
            next = nil
        }
    }

    /// Fetches a book's file and hands it to whoever reads files into the library.
    func take(_ entry: OPDSEntry) async {
        guard
            let acquisition = entry.preferred(among: Self.wanted)
        else { return message = String(localized: "This catalogue offers no FB2 for that book") }
        guard let client, let inbox else { return }

        fetching = entry.id
        message = nil
        defer { fetching = nil }

        do {
            let data = try await client.download(acquisition)
            let file = try Self.write(data, named: entry.title, as: acquisition.kind)

            await inbox.accept([ file ])
        } catch {
            message = Self.wording(of: error)
        }
    }

    private enum Failure: Error {
        /// The catalogue offers nothing of the kind asked for.
        case noSection
    }

    /// Runs one fetch, with everything the screen reads off it kept in step.
    private func load(_ work: @escaping () async throws -> OPDSPage) async {
        isLoading = true
        message = nil
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            let page = try await work()

            entries = page.entries
            next = page.next
        } catch {
            entries = []
            next = nil
            message = Self.wording(of: error)
        }
    }

    /// The client for an address, made again where the address has changed.
    private func client(for address: String) -> OPDSClient? {
        if self.address == address, let client { return client }

        guard
            let root = Self.url(from: address)
        else {
            message = String(localized: "That address doesn't look right")
            return nil
        }

        let made = OPDSClient(root: root)

        client = made
        self.address = address
        return made
    }

    /// The address as a URL, forgiving a reader who left the scheme off.
    static func url(from address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return nil }

        return URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)")
    }

    private static func write(_ data: Data, named title: String, as kind: OPDSAcquisition.Kind) throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("opds", isDirectory: true)

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let safe = title.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|")).joined(separator: " ")
        let file =
            folder
            .appendingPathComponent(safe.isEmpty ? "book" : safe)
            .appendingPathExtension(kind == .fb2Zip ? "fb2.zip" : "fb2")

        try data.write(to: file, options: .atomic)
        return file
    }

    private static func wording(of error: any Error) -> String {
        if error is Failure { return String(localized: "This catalogue offers nothing of that kind") }

        return switch error as? OPDSClient.Failure {
            case .noSearch: String(localized: "This catalogue offers no search")
            case .notAFeed: String(localized: "That address answered with something else")
            case .badAddress: String(localized: "That address doesn't look right")
            default: error.localizedDescription
        }
    }
}
