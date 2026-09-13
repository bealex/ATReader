//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Foundation
import Testing

@testable import BookFormats

/// Reading a book out of an EPUB. Every book here is generated nonsense, built into a real archive so
/// the reader is checked against bytes rather than against a mock of itself.
struct EpubFormatTests {
    // MARK: - What a book is

    @Test
    func readsWhatThePackageSaysTheBookIs() throws {
        let book = try EpubFormat.parse(Self.archive())

        #expect(book.title == "Alpha Bravo")
        #expect(book.authors == [ "Charlie Delta" ])
        #expect(book.language == "en")
        #expect(book.identifier == "urn:uuid:echo-foxtrot")
        #expect(book.format == "epub")
        #expect(book.fingerprint.hasPrefix("epub:id:"))
    }

    @Test
    func namesEachChapterTheWayTheNavigationDoes() throws {
        let book = try EpubFormat.parse(Self.archive())

        #expect(book.sections.count == 2)
        #expect(book.sections[0].title == "Golf")
        #expect(book.sections[1].title == "Hotel")
        #expect(book.sections.allSatisfy { $0.textLength > 0 })
    }

    @Test
    func filesAnAuthorTheWayTheyAreRead() throws {
        let book = try EpubFormat.parse(Self.archive(creator: "Delta, Charlie"))

        #expect(book.authors == [ "Charlie Delta" ])
    }

    @Test
    func readsTheSeriesCalibreWroteAndTheVolumeWithIt() throws {
        let extra = """
            <meta name="calibre:series" content="India"/>
            <meta name="calibre:series_index" content="4"/>
            """
        let book = try EpubFormat.parse(Self.archive(metadata: extra))

        #expect(book.series == "India")
        #expect(book.seriesOrder == 4)
    }

    // MARK: - What the chapters hold

    @Test
    func keepsEmphasisAsTheBookMarkedIt() {
        let read = BookHTML.chapter(from: "<p>Juliett <em>kilo</em> and <strong>lima</strong>.</p>")
        let paragraph = read.paragraphs[0]

        #expect(paragraph.text == "Juliett kilo and lima.")
        #expect(paragraph.styles.count == 2)

        let italic = paragraph.styles.first { $0.emphasis == .italic }
        let bold = paragraph.styles.first { $0.emphasis == .bold }

        #expect(italic.map { paragraph.text.slice($0.range) } == "kilo")
        #expect(bold.map { paragraph.text.slice($0.range) } == "lima")
    }

    @Test
    func marksAPhraseSetBothWays() {
        let read = BookHTML.chapter(from: "<p>Mike <b><i>november</i></b> oscar.</p>")
        let paragraph = read.paragraphs[0]

        #expect(paragraph.styles.count == 2)
        #expect(Set(paragraph.styles.map(\.emphasis)) == [ .italic, .bold ])
        #expect(paragraph.styles.allSatisfy { paragraph.text.slice($0.range) == "november" })
    }

    @Test
    func readsAListAsItemsThatCarryTheirOwnMark() throws {
        let chapter = "<h1>Papa</h1><ul><li>quebec</li><li>romeo</li></ul><ol><li>sierra</li></ol>"
        let book = try EpubFormat.parse(Self.archive(first: chapter))
        let paragraphs = BookHTML.paragraphs(from: book.sections[0].html)

        #expect(paragraphs.contains { $0.text == "• quebec" && $0.listLevel == 1 })
        #expect(paragraphs.contains { $0.text == "• romeo" && $0.listLevel == 1 })
        #expect(paragraphs.contains { $0.text == "1. sierra" && $0.listLevel == 1 })
    }

    @Test
    func centresWhatTheStylesheetCentres() throws {
        let chapter = "<h1>Tango</h1><p class=\"mid\">uniform</p><p>victor</p>"
        let book = try EpubFormat.parse(Self.archive(first: chapter, css: ".mid { text-align: center; }"))
        let paragraphs = BookHTML.paragraphs(from: book.sections[0].html)

        #expect(paragraphs.first { $0.text == "uniform" }?.isCentered == true)
        #expect(paragraphs.first { $0.text == "victor" }?.isCentered == false)
    }

    @Test
    func carriesANoteIntoTheChapterThatPointsAtIt() throws {
        let chapter = """
            <h1>Whiskey</h1>
            <p>xray<a epub:type="noteref" href="#n1">1</a> yankee.</p>
            <aside epub:type="footnote" id="n1"><p>zulu the note</p></aside>
            """
        let book = try EpubFormat.parse(Self.archive(first: chapter))
        let read = BookHTML.chapter(from: book.sections[0].html)

        #expect(read.notes.count == 1)
        #expect(read.notes.values.first?.text == "zulu the note")
        #expect(read.paragraphs.contains { $0.notes.count == 1 })
    }

    @Test
    func cutsADocumentWhereTheNavigationSaysItsChaptersAre() throws {
        let chapter = """
            <h2 id="c1">Alfa one</h2><p>one one one</p>
            <h2 id="c2">Alfa two</h2><p>two two two</p>
            <h2 id="c3">Alfa three</h2><p>three three three</p>
            """
        let book = try EpubFormat.parse(Self.archive(
            first: chapter,
            navigation: (1 ... 3).map { ("first.xhtml#c\($0)", "Alfa \([ "one", "two", "three" ][$0 - 1])") }
        ))

        // Three out of the one document, and the book's second document behind them.
        #expect(book.sections.count == 4)
        #expect(book.sections.prefix(3).map(\.title) == [ "Alfa one", "Alfa two", "Alfa three" ])
        #expect(book.sections.last?.title == "Hotel")
    }

    @Test
    func marksTheBlockALinkLandsOn() throws {
        let chapter = """
            <h1>Papa</h1>
            <p>Turn to <a href="second.xhtml#far">the second chapter</a> for the rest.</p>
            """
        let second = "<h1>Hotel</h1><p id=\"far\">The place it points at.</p>"
        let book = try EpubFormat.parse(Self.archive(first: chapter, second: second))
        let read = BookHTML.chapter(from: book.sections[0].html)
        let landing = BookHTML.paragraphs(from: book.sections[1].html)

        let target = try #require(read.paragraphs.compactMap(\.links.first).first?.target)

        #expect(landing.contains { $0.anchor == target })
    }

    @Test
    func leavesAnOutwardLinkAsPlainWords() throws {
        let chapter = "<h1>Papa</h1><p>See <a href=\"https://example.com\">a website</a> instead.</p>"
        let book = try EpubFormat.parse(Self.archive(first: chapter))
        let read = BookHTML.chapter(from: book.sections[0].html)

        #expect(read.paragraphs.allSatisfy { $0.links.isEmpty })
        #expect(read.paragraphs.contains { $0.text.contains("a website") })
    }

    @Test
    func dropsAPageThatIsMostlyLinksIntoTheBook() throws {
        let listed = (1 ... 8).map { "<p><a href=\"second.xhtml#c\($0)\">Chapter \($0) of the book</a></p>" }
        let book = try EpubFormat.parse(Self.archive(first: "<h1>Papa</h1>" + listed.joined()))

        #expect(!book.sections.contains { $0.title == "Golf" })
    }

    @Test
    func takesANoteFromTheBlockItsAnchorStandsBefore() throws {
        // The shape books actually use: an empty anchor in a paragraph of its own, and the note in
        // the one after it.
        let chapter = "<h1>Papa</h1><p>Quebec<a href=\"second.xhtml#n1\">[2]</a> romeo.</p>"
        let second = """
            <h1>Hotel</h1>
            <p><a id="n1"/></p>
            <p class="footnote"><a href="first.xhtml#back">[2]</a> Sierra the note itself.</p>
            """
        let book = try EpubFormat.parse(Self.archive(first: chapter, second: second))
        let read = BookHTML.chapter(from: book.sections[0].html)

        #expect(read.notes.count == 1)
        // The marker the note opens with is how it is named where it is shown, so it does not also
        // stand at the head of its own words.
        #expect(read.notes.values.first?.text == "Sierra the note itself.")
        #expect(read.paragraphs.contains { $0.notes.count == 1 })
        // A note is shown where it stands rather than turned to, so its marker is no link.
        #expect(read.paragraphs.allSatisfy { $0.links.isEmpty })
    }

    @Test
    func standsAMarkerAgainstTheWordItBelongsTo() throws {
        // A book spaces a marker off after a word and not after a comma. Both belong against it.
        let chapter = """
            <h1>Papa</h1>
            <p>Quebec <a href="second.xhtml#n1">[2]</a> romeo, and sierra<a href="second.xhtml#n2">[3]</a> tango.</p>
            """
        let second = """
            <h1>Hotel</h1>
            <p><a id="n1"/></p><p>The first note.</p>
            <p><a id="n2"/></p><p>The second note.</p>
            """
        let book = try EpubFormat.parse(Self.archive(first: chapter, second: second))
        let read = BookHTML.chapter(from: book.sections[0].html)
        let text = try #require(read.paragraphs.first { $0.notes.count == 2 }?.text)

        #expect(text.contains("Quebec[2]"))
        #expect(text.contains("sierra[3]"))
        #expect(!text.contains("Quebec [2]"))
    }

    // MARK: - Which way the book reads

    @Test
    func marksAnArabicBookAsReadFromTheRight() throws {
        let book = try EpubFormat.parse(Self.archive(language: "ar"))
        let paragraphs = BookHTML.paragraphs(from: book.sections[0].html)

        #expect(paragraphs.allSatisfy { $0.isRightToLeft })
    }

    @Test
    func takesTheSpineAtItsWordAboutTheDirection() throws {
        let book = try EpubFormat.parse(Self.archive(progression: "rtl"))
        let paragraphs = BookHTML.paragraphs(from: book.sections[0].html)

        #expect(paragraphs.allSatisfy { $0.isRightToLeft })
    }

    @Test
    func leavesAnOrdinaryBookReadingFromTheLeft() throws {
        let book = try EpubFormat.parse(Self.archive())
        let paragraphs = BookHTML.paragraphs(from: book.sections[0].html)

        #expect(paragraphs.allSatisfy { !$0.isRightToLeft })
    }

    // MARK: - Books this reader turns down

    @Test
    func refusesABookSomebodyHasLocked() throws {
        let sealed = Zip.File(
            "META-INF/encryption.xml",
            """
            <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <EncryptedData><EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes256-cbc"/></EncryptedData>
            </encryption>
            """
        )

        #expect(throws: BookFileError.self) { try EpubFormat.parse(Self.archive(extra: [ sealed ])) }
    }

    @Test
    func readsABookWhoseOnlyLockIsOnItsFonts() throws {
        let obscured = Zip.File(
            "META-INF/encryption.xml",
            """
            <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <EncryptedData><EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/></EncryptedData>
            </encryption>
            """
        )
        let book = try EpubFormat.parse(Self.archive(extra: [ obscured ]))

        #expect(book.sections.count == 2)
    }

    @Test
    func refusesABookSetPageByPage() throws {
        let fixed = "<meta property=\"rendition:layout\">pre-paginated</meta>"

        #expect(throws: BookFileError.self) { try EpubFormat.parse(Self.archive(metadata: fixed)) }
    }

    @Test
    func turnsDownBytesThatAreNotABook() {
        #expect(!EpubFormat().canRead(Data("not an archive".utf8)))
        #expect(!EpubFormat().canRead(Zip.archive([ Zip.File("hello.txt", "world") ])))
        #expect(EpubFormat().canRead(Self.archive()))
    }

    // MARK: - Archives

    @Test
    func readsAnArchiveTooBigForItsOwnRecords() throws {
        let book = try EpubFormat.parse(Self.archive(wide: true))

        #expect(book.title == "Alpha Bravo")
        #expect(book.sections.count == 2)
    }

    @Test
    func readsAMemberByTheNameItsMarkupUsesForIt() throws {
        let archive = Zip.archive([ Zip.File("OEBPS/a b.xhtml", "sierra") ])
        let reader = try ZipReader(archive)

        #expect(reader.text(named: "OEBPS/a%20b.xhtml") == "sierra")
        #expect(reader.text(named: "OEBPS/a b.xhtml") == "sierra")
        #expect(reader.member(named: "OEBPS/nothing.xhtml") == nil)
    }

    // MARK: - The book under test

    /// A two-chapter book, built whole so each test can move one thing about it.
    private static func archive(
        creator: String = "Charlie Delta",
        language: String = "en",
        metadata: String = "",
        progression: String = "ltr",
        first: String = "<h1>Golf</h1><p>The first chapter of it.</p>",
        second: String = "<h1>Hotel</h1><p>The second chapter of it.</p>",
        css: String = "",
        navigation: [(String, String)] = [ ("first.xhtml", "Golf"), ("second.xhtml", "Hotel") ],
        extra: [Zip.File] = [],
        wide: Bool = false
    ) -> Data {
        let links =
            navigation
            .map { "<li><a href=\"\($0.0)\">\($0.1)</a></li>" }
            .joined()

        let files: [Zip.File] = [
            Zip.File("mimetype", "application/epub+zip"),
            Zip.File(
                "META-INF/container.xml",
                """
                <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
                  <rootfiles>
                    <rootfile full-path="OEBPS/book.opf" media-type="application/oebps-package+xml"/>
                  </rootfiles>
                </container>
                """
            ),
            Zip.File("OEBPS/book.opf", package(creator, language, metadata, progression)),
            Zip.File(
                "OEBPS/nav.xhtml",
                """
                <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
                  <body><nav epub:type="toc"><ol>\(links)</ol></nav></body>
                </html>
                """
            ),
            Zip.File("OEBPS/book.css", css),
            Zip.File("OEBPS/first.xhtml", document(first)),
            Zip.File("OEBPS/second.xhtml", document(second)),
        ]

        return Zip.archive(files + extra, wide: wide)
    }

    /// The package document, which is most of what a test moves about.
    private static func package(
        _ creator: String,
        _ language: String,
        _ metadata: String,
        _ progression: String
    ) -> String {
        """
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Alpha Bravo</dc:title>
            <dc:creator>\(creator)</dc:creator>
            <dc:language>\(language)</dc:language>
            <dc:identifier id="pub-id">urn:uuid:echo-foxtrot</dc:identifier>
            \(metadata)
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="one" href="first.xhtml" media-type="application/xhtml+xml"/>
            <item id="two" href="second.xhtml" media-type="application/xhtml+xml"/>
            <item id="css" href="book.css" media-type="text/css"/>
          </manifest>
          <spine page-progression-direction="\(progression)">
            <itemref idref="one"/>
            <itemref idref="two"/>
          </spine>
        </package>
        """
    }

    private static func document(_ body: String) -> String {
        """
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
          <head><title>Ignored</title><link rel="stylesheet" href="book.css"/></head>
          <body>\(body)</body>
        </html>
        """
    }
}

extension String {
    /// The characters a mark covers, counted the way a mark counts them.
    fileprivate func slice(_ range: NSRange) -> String {
        (self as NSString).substring(with: range)
    }
}
