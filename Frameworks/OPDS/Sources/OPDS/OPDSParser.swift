//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// Reads the two XML documents a catalogue answers with: its Atom feed, and the OpenSearch
/// description that says where to put a query.
///
/// `XMLParser` rather than a parser of our own, since Foundation already has one and a catalogue's
/// answer is ordinary XML with none of HTML's forgiveness needed.
enum OPDSParser {
    static func feed(in data: Data, from url: URL) -> OPDSFeed? {
        let reader = FeedReader(base: url)
        let parser = XMLParser(data: data)

        parser.delegate = reader
        parser.shouldProcessNamespaces = true

        guard parser.parse() else { return nil }

        return reader.feed
    }

    /// The search address an OpenSearch description offers, preferring the one that answers in Atom.
    static func search(in data: Data) -> OPDSSearch? {
        let reader = SearchReader()
        let parser = XMLParser(data: data)

        parser.delegate = reader
        parser.shouldProcessNamespaces = true

        guard parser.parse() else { return nil }
        guard let template = reader.template else { return nil }

        return OPDSSearch(template: template, firstPage: reader.firstPage)
    }

    /// What the acquisition links are called, in the spellings catalogues actually use.
    private static let acquisitionRelations = [
        "http://opds-spec.org/acquisition",
        "http://opds-spec.org/acquisition/open-access",
        "http://opds-spec.org/acquisition/buy",
    ]

    private static func isAcquisition(_ relation: String) -> Bool {
        acquisitionRelations.contains { relation == $0 || relation.hasPrefix($0 + "/") }
    }

    /// One pass down an Atom feed, gathering whole entries as their closing tags come round.
    private final class FeedReader: NSObject, XMLParserDelegate {
        private let base: URL
        private var feedTitle: String?
        private var entries: [OPDSEntry] = []
        private var searchDescription: URL?
        private var searchTemplate: String?
        private var next: URL?

        /// What is being gathered, where an entry is open.
        private var open: Entry?
        private var text = ""
        private var isInsideAuthor = false

        private struct Entry {
            var id = ""
            var title = ""
            var authors: [String] = []
            var summary: String?
            var language: String?
            var acquisitions: [OPDSAcquisition] = []
            var navigation: URL?
        }

        init(base: URL) {
            self.base = base
        }

        var feed: OPDSFeed {
            OPDSFeed(
                title: feedTitle,
                entries: entries,
                searchDescription: searchDescription,
                searchTemplate: searchTemplate,
                next: next
            )
        }

        func parser(
            _ parser: XMLParser,
            didStartElement element: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String]
        ) {
            text = ""

            switch element {
                case "entry": open = Entry()
                case "author": isInsideAuthor = true
                case "link": read(link: attributes)
                default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters found: String) {
            text += found
        }

        func parser(
            _ parser: XMLParser,
            didEndElement element: String,
            namespaceURI: String?,
            qualifiedName: String?
        ) {
            let written = text.trimmingCharacters(in: .whitespacesAndNewlines)

            switch element {
                case "entry":
                    if let open, !open.title.isEmpty {
                        entries.append(OPDSEntry(
                            id: open.id.isEmpty ? open.title : open.id,
                            title: open.title,
                            authors: open.authors,
                            summary: open.summary,
                            language: open.language,
                            acquisitions: open.acquisitions,
                            navigation: open.navigation
                        ))
                    }

                    open = nil
                case "author": isInsideAuthor = false
                case "name" where isInsideAuthor:
                    if !written.isEmpty { open?.authors.append(written) }
                case "title":
                    if open != nil { open?.title = written } else if feedTitle == nil { feedTitle = written }
                case "id":
                    if open?.id.isEmpty == true { open?.id = written }
                case "summary", "content":
                    if open?.summary == nil, !written.isEmpty { open?.summary = written }
                case "language":
                    if open?.language == nil, !written.isEmpty { open?.language = written }
                default: break
            }

            text = ""
        }

        /// A link is an acquisition, a search, or none of this reader's business.
        private func read(link attributes: [String: String]) {
            guard
                let href = attributes["href"],
                let url = URL(string: href, relativeTo: base)?.absoluteURL
            else { return }

            let relation = attributes["rel"] ?? ""
            let type = attributes["type"] ?? ""

            if open != nil {
                if OPDSParser.isAcquisition(relation) {
                    open?.acquisitions.append(OPDSAcquisition(url: url, mediaType: type))
                    return
                }

                // A section leads on to another feed. Catalogues mark those with the catalogue profile
                // and often give them no relation at all, so the type is what says so. A "related"
                // link is an aside about the entry, not the way into it.
                if open?.navigation == nil, type.contains("atom+xml"), relation != "related" {
                    open?.navigation = url
                }

                return
            }

            guard open == nil else { return }

            // The page after this one, which is how an answer is walked through: a catalogue that has
            // run out offers none.
            if relation == "next" { next = url }

            guard relation == "search" else { return }

            // Either the description to ask next, or an address already carrying its own query.
            if type.contains("opensearchdescription") {
                searchDescription = url
            } else if href.contains("{searchTerms}") {
                searchTemplate = href
            }
        }
    }

    /// One pass down an OpenSearch description, for the address that answers in Atom.
    private final class SearchReader: NSObject, XMLParserDelegate {
        private(set) var template: String?
        /// What the catalogue calls its first page. One unless it says otherwise.
        private(set) var firstPage = 1
        private var atomTemplate: String?

        func parser(
            _ parser: XMLParser,
            didStartElement element: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String]
        ) {
            guard
                element.caseInsensitiveCompare("Url") == .orderedSame,
                let found = attributes["template"],
                found.contains("{searchTerms}")
            else { return }

            let type = (attributes["type"] ?? "").lowercased()

            if type.contains("atom") { atomTemplate = atomTemplate ?? found }

            template = atomTemplate ?? template ?? found

            if let offset = attributes["pageOffset"].flatMap(Int.init) { firstPage = offset }
        }

        func parserDidEndDocument(_ parser: XMLParser) {
            template = atomTemplate ?? template
        }
    }
}
