//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// What a book's own navigation calls each of its pieces, and how deep each one stands.
///
/// This is the whole reason an EPUB needs no guessing at where its chapters are: the spine says what
/// order the documents read in and the navigation says what they are called, where FB2 leaves both to
/// be inferred from how its sections nest.
struct EpubNavigation {
    struct Entry {
        /// The document it points at, resolved against the navigation's own directory.
        let path: String
        /// Where inside that document, where it names a place rather than a whole file.
        let fragment: String?
        let title: String
        /// One for a piece the book names outright, more for anything listed inside one.
        let level: Int
    }

    var entries: [Entry] = []

    /// True where the navigation says nothing useful, so the book has to be cut some other way.
    var isEmpty: Bool { entries.isEmpty }

    /// What the book calls the document at this path, and how deep each piece of it stands.
    ///
    /// More than one where the book keeps several chapters in one file, which is how a book made from
    /// one long transcription arrives. Each entry's fragment is where that chapter starts.
    func entries(forPath path: String) -> [Entry] {
        entries.filter { $0.path == path }
    }

    // MARK: - Reading one

    /// The navigation an EPUB carries, preferring its own over the one it keeps for older readers.
    static func read(_ package: EpubPackage, from archive: ZipReader) -> EpubNavigation {
        if let item = package.navigation, let text = archive.text(named: item.path) {
            let read = fromNavigationDocument(Markup.parse(text), base: directory(of: item.path))

            if !read.isEmpty { return read }
        }

        guard let item = package.contents, let text = archive.text(named: item.path) else { return EpubNavigation() }

        return fromContents(Markup.parse(text), base: directory(of: item.path))
    }

    /// The EPUB 3 navigation document: a list of links, nested as deep as the book divides itself.
    private static func fromNavigationDocument(_ root: Markup.Node, base: String) -> EpubNavigation {
        let navigations = root.all("nav")
        // The one marked as the table of contents, or the first where nothing is marked: a file also
        // carries a list of printed pages and a list of landmarks, and neither names a chapter.
        let chosen =
            navigations.first { $0.isMarked("toc") }
            ?? navigations.first { !$0.isMarked("page-list") && !$0.isMarked("landmarks") }

        guard let chosen, let list = chosen.first("ol") else { return EpubNavigation() }

        var navigation = EpubNavigation()

        navigation.readList(list, base: base, level: 1)
        return navigation
    }

    private mutating func readList(_ list: Markup.Node, base: String, level: Int) {
        for item in list.children("li") {
            // The link is the item's own, not one belonging to a list nested inside it.
            if let link = item.children.first(where: { $0.name == "a" || $0.name == "span" }) {
                append(link.attributes["href"], title: link.words, base: base, level: level)
            }

            for nested in item.children("ol") { readList(nested, base: base, level: level + 1) }
        }
    }

    /// The EPUB 2 table of contents, which nearly every file still carries beside its own.
    private static func fromContents(_ root: Markup.Node, base: String) -> EpubNavigation {
        guard let map = root.first("navmap") else { return EpubNavigation() }

        var navigation = EpubNavigation()

        navigation.readPoints(in: map, base: base, level: 1)
        return navigation
    }

    private mutating func readPoints(in parent: Markup.Node, base: String, level: Int) {
        for point in parent.children("navpoint") {
            let title = point.first("navlabel")?.first("text")?.words ?? point.first("text")?.words ?? ""

            append(point.first("content")?.attributes["src"], title: title, base: base, level: level)
            readPoints(in: point, base: base, level: level + 1)
        }
    }

    private mutating func append(_ href: String?, title: String, base: String, level: Int) {
        guard let href, let title = title.trimmed.nilWhenEmpty else { return }

        let fragment = href.split(separator: "#", maxSplits: 1).dropFirst().first.map(String.init)

        entries.append(Entry(
            path: EpubPackage.resolve(href, against: base),
            fragment: fragment,
            title: title,
            level: level
        ))
    }

    private static func directory(of path: String) -> String { (path as NSString).deletingLastPathComponent }
}
