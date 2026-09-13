//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// What an EPUB's package document says: what the book is, what it holds, and in what order it reads.
struct EpubPackage {
    /// One file the publication is made of.
    struct Item {
        let id: String
        /// Where it stands in the archive, resolved against the package document's own directory.
        let path: String
        let mediaType: String
        let properties: String

        var isImage: Bool { mediaType.hasPrefix("image/") }
        var isDocument: Bool { mediaType.contains("xhtml") || mediaType.contains("html") }
    }

    var title: String?
    var authors: [String] = []
    var language: String?
    var identifier: String?
    var annotation: String?
    var series: String?
    var seriesOrder: Int?

    /// The book reads right to left, which its spine says outright and its language implies.
    var readsRightToLeft = false
    /// The book is set page by page, which this reader has no way to reflow.
    var isFixedLayout = false

    var items: [String: Item] = [:]
    /// The documents the book reads through, in order.
    var spine: [Item] = []
    var cover: Item?
    /// The EPUB 3 navigation document, where the book carries one.
    var navigation: Item?
    /// The EPUB 2 table of contents, which most files still carry as well.
    var contents: Item?

    // MARK: - Reading one out of an archive

    /// The package the archive's own container points at.
    static func read(from archive: ZipReader) throws -> EpubPackage {
        try refuseIfSealed(archive)

        guard
            let container = archive.text(named: "META-INF/container.xml")
        else { throw BookFileError.malformed("no EPUB container") }

        let rootfiles = Markup.parse(container).all("rootfile")
        let path = rootfiles.compactMap { $0.attributes["full-path"] }.first { archive.has($0) }

        guard
            let path,
            let text = archive.text(named: path)
        else { throw BookFileError.malformed("no EPUB package document") }

        return read(Markup.parse(text), base: (path as NSString).deletingLastPathComponent)
    }

    /// The algorithms an EPUB is allowed to use on its own files without being sealed against reading.
    ///
    /// Both obscure an embedded font so it cannot be lifted out and installed, which changes nothing
    /// here: this reader sets a book in the face the reader chose and never opens the book's own.
    private static let obfuscations: Set<String> = [
        "http://www.idpf.org/2008/embedding",
        "http://ns.adobe.com/pdf/enc#RC",
    ]

    /// Refuses a book somebody has locked, rather than showing its reader a chapter of noise.
    private static func refuseIfSealed(_ archive: ZipReader) throws {
        if archive.has("META-INF/rights.xml") { throw BookFileError.protectedBook }

        guard let encryption = archive.text(named: "META-INF/encryption.xml") else { return }

        let algorithms = Markup.parse(encryption).all("encryptionmethod")
            .compactMap { $0.attributes["algorithm"] }

        guard algorithms.allSatisfy(obfuscations.contains) else { throw BookFileError.protectedBook }
    }

    private static func read(_ root: Markup.Node, base: String) -> EpubPackage {
        var package = EpubPackage()

        guard let document = root.first("package") ?? root.elements.first else { return package }

        package.readItems(document, base: base)
        package.readMetadata(document)
        package.readSpine(document)
        return package
    }

    // MARK: - What the book is

    private mutating func readMetadata(_ document: Markup.Node) {
        guard let metadata = document.first("metadata") else { return }

        // EPUB 3 hangs a fact about another element off it by id, which is how a creator is known to
        // be the author rather than the translator and a collection to be a series rather than a set.
        var refinements: [String: [String: String]] = [:]

        for meta in metadata.children("meta") {
            guard
                let refines = meta.attributes["refines"],
                refines.hasPrefix("#"),
                let property = meta.attributes["property"]
            else { continue }

            refinements[String(refines.dropFirst()), default: [:]][property.lowercased()] = meta.words
        }

        title = metadata.first("title")?.words.nilWhenEmpty
        language = metadata.first("language")?.words.nilWhenEmpty
        annotation = metadata.first("description").map { Self.plainWords($0.words) }?.nilWhenEmpty
        identifier = readIdentifier(document, metadata: metadata)
        authors = Self.authors(in: metadata, refinements: refinements)
        readSeries(metadata, refinements: refinements)

        if let language, Self.isRightToLeft(language) { readsRightToLeft = true }

        let layouts = metadata.children("meta")
            .filter { $0.attributes["property"]?.lowercased() == "rendition:layout" }
            .map(\.words)

        if layouts.contains(where: { $0.contains("pre-paginated") }) { isFixedLayout = true }
    }

    /// The identifier the package itself points at, rather than whichever one stands first.
    ///
    /// A file often carries several: the one it is published under, an ISBN, and whatever the tool
    /// that made it left behind. Only the one the package names is stable across its editions.
    private func readIdentifier(_ document: Markup.Node, metadata: Markup.Node) -> String? {
        let identifiers = metadata.children("identifier")
        let named = document.attributes["unique-identifier"]

        let chosen =
            identifiers.first { $0.attributes["id"] == named && named != nil }
            ?? identifiers.first

        return chosen?.words.nilWhenEmpty
    }

    private static func authors(in metadata: Markup.Node, refinements: [String: [String: String]]) -> [String] {
        let creators = metadata.children("creator")
        // A file that says what each of its people did names its author among them. One that says
        // nothing is taken at its word, since a book with no author named reads worse than one with a
        // translator's name on it.
        let written = creators.filter { creator in
            let role = creator.attributes["role"] ?? creator.attributes["id"].flatMap { refinements[$0]?["role"] }

            return role == nil || role == "aut"
        }

        let chosen = written.isEmpty ? creators : written

        return chosen.compactMap { name($0.words) }
    }

    /// A person's name as it is read out, rather than as it is filed.
    ///
    /// Files that sort their people write the surname first with a comma after it, and a shelf full of
    /// "Surname, Forename" reads like a catalogue.
    private static func name(_ written: String) -> String? {
        let trimmed = written.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: ",", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return trimmed }

        return "\(parts[1]) \(parts[0])"
    }

    private mutating func readSeries(_ metadata: Markup.Node, refinements: [String: [String: String]]) {
        let metas = metadata.children("meta")

        // Calibre wrote the series long before the format had a word for one, and most files on a
        // device were made by it.
        if let named = metas.first(where: { $0.attributes["name"] == "calibre:series" }) {
            series = named.attributes["content"]?.nilWhenEmpty
            seriesOrder = metas.first { $0.attributes["name"] == "calibre:series_index" }?
                .attributes["content"]
                .flatMap { Int($0.prefix(while: \.isNumber)) }
        }

        guard series == nil else { return }

        for meta in metas where meta.attributes["property"]?.lowercased() == "belongs-to-collection" {
            let facts = meta.attributes["id"].flatMap { refinements[$0] } ?? [:]

            // A collection is a series only where it says so. The other kind gathers a publisher's
            // books, which is not a place in a story.
            guard facts["collection-type"] ?? "series" == "series" else { continue }

            series = meta.words.nilWhenEmpty
            seriesOrder = facts["group-position"].flatMap { Int($0.prefix(while: \.isNumber)) }
            return
        }
    }

    // MARK: - What the book holds

    private mutating func readItems(_ document: Markup.Node, base: String) {
        guard let manifest = document.first("manifest") else { return }

        for element in manifest.children("item") {
            guard let id = element.attributes["id"], let href = element.attributes["href"] else { continue }

            let item = Item(
                id: id,
                path: Self.resolve(href, against: base),
                mediaType: element.attributes["media-type"] ?? "",
                properties: element.attributes["properties"] ?? ""
            )

            items[id] = item

            if item.properties.contains("nav") { navigation = item }

            if item.mediaType.contains("dtbncx") { contents = item }

            if item.properties.contains("cover-image") { cover = item }
        }

        // The older way of naming a cover, which is a pointer from the metadata rather than a mark on
        // the file itself.
        if cover == nil {
            let named = document.first("metadata")?.children("meta")
                .first { $0.attributes["name"] == "cover" }?
                .attributes["content"]

            let item = named.flatMap { items[$0] }

            cover = (item?.isImage ?? false) ? item : nil
        }
    }

    private mutating func readSpine(_ document: Markup.Node) {
        guard let element = document.first("spine") else { return }

        if element.attributes["page-progression-direction"] == "rtl" { readsRightToLeft = true }

        if contents == nil { contents = element.attributes["toc"].flatMap { items[$0] } }

        for reference in element.children("itemref") {
            guard let item = reference.attributes["idref"].flatMap({ items[$0] }) else { continue }

            if reference.attributes["properties"]?.contains("rendition:layout-pre-paginated") == true {
                isFixedLayout = true
            }

            // A document the spine marks as out of the reading order is a cover plate or a colophon,
            // which the book is no worse for leaving out.
            guard reference.attributes["linear"] != "no" else { continue }

            spine.append(item)
        }
    }

    // MARK: - Paths

    /// A path inside the archive, given one written relative to the document that named it.
    ///
    /// Fragments go: what a chapter is called from is the file, and where inside it the reader lands is
    /// not something this reader can honour.
    static func resolve(_ href: String, against base: String) -> String {
        let plain = href.prefix { $0 != "#" && $0 != "?" }
        let decoded = String(plain).removingPercentEncoding ?? String(plain)

        guard !decoded.hasPrefix("/") else { return normalised(String(decoded.dropFirst())) }

        return normalised(base.isEmpty ? decoded : base + "/" + decoded)
    }

    private static func normalised(_ path: String) -> String {
        var parts: [String] = []

        for piece in path.split(separator: "/") {
            switch piece {
                case ".": continue
                case "..": _ = parts.popLast()
                default: parts.append(String(piece))
            }
        }

        return parts.joined(separator: "/")
    }

    /// Languages written from the right, which the reader sets and turns the other way round.
    static func isRightToLeft(_ language: String) -> Bool {
        let tag = language.lowercased().prefix { $0 != "-" && $0 != "_" }

        return [ "ar", "he", "fa", "ur", "yi", "ps", "sd", "ug", "dv", "ku", "az" ].contains(String(tag))
    }

    /// A description as words, since a file is as likely to write one as markup as as text.
    private static func plainWords(_ text: String) -> String {
        Entities.decoded(text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
