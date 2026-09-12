//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import Testing

@testable import OPDS

/// What a catalogue's answer comes out as. The feeds here are written for the test: no catalogue was
/// asked for any of it.
struct OPDSParserTests {
    private static let root = URL(string: "https://books.example/opds/")!

    private func feed(_ xml: String) -> OPDSFeed? {
        OPDSParser.feed(in: Data(xml.utf8), from: Self.root)
    }

    @Test
    func readsABookOutOfAnEntry() throws {
        let found = try #require(
            feed(
                """
                <feed xmlns="http://www.w3.org/2005/Atom">
                  <title>Каталог</title>
                  <entry>
                    <id>urn:book:1</id>
                    <title>Название книги</title>
                    <author><name>Первый Автор</name></author>
                    <author><name>Второй Автор</name></author>
                    <summary>О чём она.</summary>
                    <link rel="http://opds-spec.org/acquisition" href="/get/1.fb2.zip" type="application/fb2+zip"/>
                  </entry>
                </feed>
                """
            )
        )

        #expect(found.title == "Каталог")
        #expect(found.entries.count == 1)

        let book = try #require(found.entries.first)

        #expect(book.id == "urn:book:1")
        #expect(book.title == "Название книги")
        #expect(book.authors == [ "Первый Автор", "Второй Автор" ])
        #expect(book.summary == "О чём она.")
        #expect(book.acquisitions.count == 1)
        #expect(book.acquisitions.first?.kind == .fb2Zip)
        // Relative addresses are resolved against the catalogue they came from.
        #expect(book.acquisitions.first?.url.absoluteString == "https://books.example/get/1.fb2.zip")
    }

    /// A catalogue that sends a bare media type and puts the shape in the path alone is still read.
    @Test(arguments: [
        ("application/fb2+zip", "/get/1", OPDSAcquisition.Kind.fb2Zip),
        ("application/fb2", "/get/1", OPDSAcquisition.Kind.fb2),
        ("application/octet-stream", "/get/1.fb2.zip", OPDSAcquisition.Kind.fb2Zip),
        ("application/octet-stream", "/get/1.fb2", OPDSAcquisition.Kind.fb2),
        ("application/epub+zip", "/get/1.epub", OPDSAcquisition.Kind.epub),
        ("application/pdf", "/get/1.pdf", OPDSAcquisition.Kind.other),
    ])
    func readsTheShapeFromTheTypeOrThePath(type: String, path: String, kind: OPDSAcquisition.Kind) throws {
        let url = try #require(URL(string: path, relativeTo: Self.root))

        #expect(OPDSAcquisition(url: url, mediaType: type).kind == kind)
    }

    @Test
    func takesTheBestShapeOnOffer() throws {
        let url = try #require(URL(string: "https://books.example/get/1"))
        let entry = OPDSEntry(
            id: "1",
            title: "Книга",
            authors: [],
            summary: nil,
            language: nil,
            acquisitions: [
                OPDSAcquisition(url: url, mediaType: "application/epub+zip"),
                OPDSAcquisition(url: url, mediaType: "application/fb2"),
                OPDSAcquisition(url: url, mediaType: "application/fb2+zip"),
            ]
        )

        #expect(entry.preferred(among: [ .fb2Zip, .fb2 ])?.kind == .fb2Zip)
        #expect(entry.preferred(among: [ .fb2, .fb2Zip ])?.kind == .fb2)
        #expect(entry.preferred(among: [ .other ]) == nil)
    }

    // MARK: - Finding the search

    @Test
    func findsTheOpenSearchDescription() throws {
        let found = try #require(
            feed(
                """
                <feed xmlns="http://www.w3.org/2005/Atom">
                  <link rel="search" type="application/opensearchdescription+xml" href="/opds/search.xml"/>
                </feed>
                """
            )
        )

        #expect(found.searchDescription?.absoluteString == "https://books.example/opds/search.xml")
        #expect(found.searchTemplate == nil)
    }

    /// Some catalogues skip the description and put the query straight on the link.
    @Test
    func findsASearchAddressGivenOutright() throws {
        let found = try #require(
            feed(
                """
                <feed xmlns="http://www.w3.org/2005/Atom">
                  <link rel="search" type="application/atom+xml" href="/opds/search?q={searchTerms}"/>
                </feed>
                """
            )
        )

        #expect(found.searchTemplate == "/opds/search?q={searchTerms}")
    }

    /// An acquisition link inside an entry is never mistaken for the feed's own search.
    @Test
    func doesNotTakeAnEntrysLinksForTheFeeds() throws {
        let found = try #require(
            feed(
                """
                <feed xmlns="http://www.w3.org/2005/Atom">
                  <entry>
                    <title>Книга</title>
                    <link rel="search" type="application/atom+xml" href="/nope?q={searchTerms}"/>
                  </entry>
                </feed>
                """
            )
        )

        #expect(found.searchTemplate == nil)
        #expect(found.entries.first?.acquisitions.isEmpty == true)
    }

    @Test
    func prefersTheDescriptionsAtomAddress() throws {
        let xml = """
            <OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
              <Url type="text/html" template="https://books.example/html?q={searchTerms}"/>
              <Url type="application/atom+xml" template="https://books.example/opds/find?q={searchTerms}"/>
            </OpenSearchDescription>
            """

        #expect(OPDSParser.search(in: Data(xml.utf8))?.template == "https://books.example/opds/find?q={searchTerms}")
    }

    /// A catalogue that counts its pages from nought says so, and is taken at its word.
    @Test
    func readsWhatTheCatalogueCallsItsFirstPage() {
        let counted = """
            <OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
              <Url type="application/atom+xml" pageOffset="0" template="/f?q={searchTerms}&amp;p={startPage?}"/>
            </OpenSearchDescription>
            """
        let plain = """
            <OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
              <Url type="application/atom+xml" template="/f?q={searchTerms}"/>
            </OpenSearchDescription>
            """

        #expect(OPDSParser.search(in: Data(counted.utf8))?.firstPage == 0)
        #expect(OPDSParser.search(in: Data(plain.utf8))?.firstPage == 1)
    }

    /// Walking an answer follows the catalogue's own next, which is the only thing that knows when the
    /// answer has run out.
    @Test
    func findsThePageAfterThisOne() throws {
        let more = try #require(
            feed(
                """
                <feed xmlns="http://www.w3.org/2005/Atom">
                  <link rel="next" href="/opds/search?q=x&amp;page=2" type="application/atom+xml"/>
                  <entry><title>Книга</title></entry>
                </feed>
                """
            )
        )
        let last = try #require(
            feed(
                """
                <feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Книга</title></entry></feed>
                """
            )
        )

        #expect(more.next?.absoluteString == "https://books.example/opds/search?q=x&page=2")
        #expect(last.next == nil)
    }

    /// The page wanted is filled in; everything else nobody filled goes.
    @Test
    func fillsInThePageWanted() {
        let made = OPDSClient.address(
            from: "/f?q={searchTerms}&page={startPage?}&count={count?}",
            query: "winnie",
            page: 0,
            against: Self.root
        )

        #expect(made?.absoluteString == "https://books.example/f?q=winnie&page=0")
    }

    // MARK: - Putting a query into a template

    @Test
    func putsTheQueryInAndDropsWhatNothingFills() throws {
        let made = OPDSClient.address(
            from: "/opds/find?q={searchTerms}&page={startPage?}",
            query: "Карма и судьба",
            against: Self.root
        )

        #expect(
            made?.absoluteString
                == "https://books.example/opds/find?q=%D0%9A%D0%B0%D1%80%D0%BC%D0%B0%20%D0%B8%20%D1%81%D1%83%D0%B4%D1%8C%D0%B1%D0%B0"
        )
    }

    /// A parameter nobody filled goes entirely, name and all. Left behind empty, a catalogue reads it
    /// as a page number of nothing and answers nothing.
    @Test(arguments: [
        ("/f?q={searchTerms}&page={startPage?}", "/f?q=winnie"),
        ("/f?q={searchTerms}&type=books&page={startPage?}", "/f?q=winnie&type=books"),
        ("/f?page={startPage?}&q={searchTerms}", "/f?q=winnie"),
        ("/f?q={searchTerms}", "/f?q=winnie"),
        ("/f/{searchTerms}", "/f/winnie"),
    ])
    func dropsWhatNothingFilledIn(template: String, wanted: String) {
        let made = OPDSClient.address(from: template, query: "winnie", against: Self.root)

        #expect(made?.path.isEmpty == false)
        #expect(made?.absoluteString.hasSuffix(wanted) == true, "\(made?.absoluteString ?? "nothing")")
    }

    @Test
    func resolvesAWholeAddressAsWellAsARelativeOne() {
        #expect(
            OPDSClient.address(from: "https://other.example/f?q={searchTerms}", query: "x", against: Self.root)?
                .absoluteString == "https://other.example/f?q=x"
        )
    }
}
