//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Foundation

/// Turns the documents a book reads through into the chapters the app shows.
///
/// A document is a chapter, which is the spine's own claim about the book and needs no guessing. The
/// one thing it doesn't settle is a file holding several chapters at once, which is how a book made
/// from one long transcription arrives, so a document carrying headings is cut at them.
enum EpubSections {
    static func make(
        _ read: [(item: EpubPackage.Item, content: EpubContent)],
        navigation: EpubNavigation,
        notes: [String: String],
        coverPath: String?,
        bookTitle: String?
    ) -> [ParsedBook.Section] {
        let named = Set(navigation.entries.map { folded($0.title) })

        return read.flatMap { item, content in
            cut(content, named: navigation.entries(forPath: item.path), bookTitle: bookTitle)
        }
        .map { carrying(notes, into: $0) }
        .filter { worthAPage($0, coverPath: coverPath) && !isContents($0, named: named) }
    }

    /// True where a piece is the book's own contents rather than a part of it.
    ///
    /// A book printed with a contents page keeps it, and a reader with a contents of its own has no use
    /// for a second one. What gives it away is structural rather than its name: nearly every line of it
    /// is a title the book's navigation also lists, which is true of no chapter.
    private static func isContents(_ section: ParsedBook.Section, named: Set<String>) -> Bool {
        guard section.textLength < longestContents else { return false }

        // Most of its words standing inside links into the book. No chapter reads like that, and it
        // holds whatever the book is called and whatever language it is in.
        if linkedShare(of: section) >= contentsShare { return true }

        let lines = blocks(in: section.html)

        guard lines.count >= fewestContentsLines else { return false }

        let listed = lines.filter { named.contains(folded($0)) }.count

        return Double(listed) / Double(lines.count) >= contentsShare
    }

    /// How much of a piece's text stands inside a link into the book.
    private static func linkedShare(of section: ParsedBook.Section) -> Double {
        guard section.textLength > 0 else { return 0 }

        var linked = 0
        var count = 0
        var cursor = section.html.startIndex

        while let open = section.html.range(of: "<a href=\"#", range: cursor ..< section.html.endIndex) {
            guard
                let opened = section.html.range(of: ">", range: open.upperBound ..< section.html.endIndex),
                let closed = section.html.range(of: "</a>", range: opened.upperBound ..< section.html.endIndex)
            else { break }

            linked += stripped(section.html[opened.upperBound ..< closed.lowerBound]).count
            count += 1
            cursor = closed.upperBound
        }

        guard count >= fewestContentsLines else { return 0 }

        return Double(linked) / Double(section.textLength)
    }

    /// A title as it is compared: its case, its spacing and its punctuation are all a publisher's
    /// habit rather than what the thing is called.
    private static func folded(_ title: String) -> String {
        title.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// The words of each block of a piece, in the order they stand.
    private static func blocks(in html: String) -> [String] {
        html.components(separatedBy: "<")
            .filter { $0.contains(">") }
            .compactMap { piece in
                piece.split(separator: ">", maxSplits: 1).dropFirst().first.map { stripped($0) }
            }
            .filter { !$0.isEmpty }
    }

    /// How long a piece may run and still be a contents rather than a chapter.
    private static let longestContents = 5000
    /// How many lines a piece needs before the share of them the navigation names says anything.
    private static let fewestContentsLines = 5
    /// What share of a contents page's lines the navigation also lists.
    private static let contentsShare = 0.6

    /// True where a piece is worth a row in the contents and a page of its own.
    ///
    /// A plate the book opens with is the cover, which the title page already shows, so a piece that
    /// holds nothing else would be the same picture twice.
    private static func worthAPage(_ section: ParsedBook.Section, coverPath: String?) -> Bool {
        guard section.textLength == 0 else { return true }

        let pictures = self.pictures(in: section.html)

        return !pictures.isEmpty && pictures.contains { $0 != coverPath }
    }

    // MARK: - Cutting a document into its chapters

    /// A document cut into the chapters its book says are in it.
    ///
    /// The navigation is what says so, and it is the one thing an EPUB states outright that FB2 leaves
    /// to be inferred: a file holding fourteen chapters carries an anchor at each of them and a list at
    /// the front naming all fourteen. Only where a document is named once, or not at all, does this
    /// fall back to reading the headings.
    private static func cut(
        _ content: EpubContent,
        named entries: [EpubNavigation.Entry],
        bookTitle: String?
    ) -> [ParsedBook.Section] {
        let marks = divisions(in: content.html)

        guard
            marks.count > 1
        else {
            return cutAtHeadings(
                content.html,
                title: entries.first?.title ?? content.heading,
                level: entries.first?.level ?? 1
            )
        }

        let titles = Dictionary(entries.compactMap { entry in entry.fragment.map { ($0, entry) } }) { first, _ in
            first
        }
        var pieces: [ParsedBook.Section] = []

        // Whatever stands before the first chapter is the document's own front matter, which the
        // navigation named nothing and which is usually the book's boilerplate.
        if let first = marks.first, first.start > content.html.startIndex {
            pieces.append(made(
                title: nil,
                html: String(content.html[content.html.startIndex ..< first.start]),
                level: entries.first?.level ?? 1
            ))
        }

        for (index, mark) in marks.enumerated() {
            let ends = index + 1 < marks.count ? marks[index + 1].start : content.html.endIndex
            let entry = titles[mark.id]

            pieces.append(made(
                title: entry?.title,
                html: String(content.html[mark.start ..< ends]),
                level: entry?.level ?? 1
            ))
        }

        return folding(pieces, bookTitle: bookTitle)
    }

    /// Pieces with every stub folded into the chapter it heads.
    ///
    /// A book that lists a chapter's number and its title as two entries of its own navigation cuts
    /// into alternating stubs and bodies, where the stub is the chapter's first line rather than a
    /// chapter. Both names are kept, since between them they are what the chapter is called.
    private static func folding(_ pieces: [ParsedBook.Section], bookTitle: String?) -> [ParsedBook.Section] {
        var folded: [ParsedBook.Section] = []
        var held: ParsedBook.Section?

        for piece in pieces {
            guard
                let stub = held
            else {
                if isStub(piece) { held = piece } else { folded.append(piece) }

                continue
            }

            held = nil
            folded.append(ParsedBook.Section(
                title: naming(stub.title, then: piece.title, of: bookTitle),
                html: stub.html + piece.html,
                textLength: stub.textLength + piece.textLength,
                level: min(stub.level, piece.level)
            ))
        }

        if let stub = held { folded.append(stub) }

        return folded
    }

    /// What a chapter is called, given the two names its navigation split it between.
    ///
    /// A stub carrying the book's own name is the title standing over the first chapter rather than
    /// half of what that chapter is called, so the chapter keeps its own name alone.
    private static func naming(_ stub: String?, then title: String?, of book: String?) -> String? {
        guard let stub else { return title }
        guard let title else { return stub }
        guard folded(stub) != book.map(folded) else { return title }

        let parted = stub.last.map { ".!?:,;—-".contains($0) } ?? false

        return parted ? "\(stub) \(title)" : "\(stub). \(title)"
    }

    /// How short a piece has to be before it reads as a chapter's heading rather than as a chapter.
    private static let shortestChapter = 60

    /// True where a piece is a heading standing on its own rather than a chapter.
    ///
    /// Both halves matter. A piece carrying a paragraph is a chapter however short it runs, which is
    /// what keeps a one-line dedication a page of its own, and a heading alone is a chapter's name
    /// however long that heading runs.
    private static func isStub(_ section: ParsedBook.Section) -> Bool {
        section.textLength < shortestChapter && !section.html.contains("<p")
    }

    /// Where each chapter of a document begins, in the order they stand.
    private static func divisions(in html: String) -> [(id: String, start: String.Index)] {
        var found: [(id: String, start: String.Index)] = []
        var cursor = html.startIndex

        while let mark = html.range(of: " data-cut=\"", range: cursor ..< html.endIndex) {
            cursor = mark.upperBound

            let id = String(html[mark.upperBound...].prefix { $0 != "\"" })

            // The block the mark belongs to starts at the bracket that opens its tag.
            guard
                let open = html.range(of: "<", options: .backwards, range: html.startIndex ..< mark.lowerBound)
            else { continue }

            found.append((id, open.lowerBound))
        }

        return found
    }

    // MARK: - Cutting a document at its own headings

    /// A document cut at the headings that divide it, for a book whose navigation named it once.
    ///
    /// Every piece cut out of a document stands one level below it, which is what the contents indents
    /// by.
    private static func cutAtHeadings(_ html: String, title: String?, level: Int) -> [ParsedBook.Section] {
        guard
            let boundaries = dividing(headings(in: html), in: html)
        else { return [ made(title: title, html: html, level: level) ] }

        var pieces: [ParsedBook.Section] = []
        // A name the document was given belongs to whichever heading spells it out, rather than to
        // whatever happened to stand above that heading. Otherwise a preface and the dedication before
        // it come out as two chapters of the same name.
        let claimed = boundaries.contains { named($0, in: html).map(folded) == title.map(folded) }

        for (index, heading) in boundaries.enumerated() {
            let ends = index + 1 < boundaries.count ? boundaries[index + 1].open.lowerBound : html.endIndex

            if index == 0, html.startIndex < heading.open.lowerBound {
                let opening = String(html[html.startIndex ..< heading.open.lowerBound])

                if !stripped(opening).isEmpty {
                    pieces.append(made(title: claimed ? nil : title, html: opening, level: level))
                }
            }

            // The heading stays in the piece it opens: a book that sets out its own divisions is left
            // to set them out, and the reader draws no heading of its own over one that does.
            pieces.append(made(
                title: named(heading, in: html),
                html: String(html[heading.open.lowerBound ..< ends]),
                level: level + 1
            ))
        }

        return pieces
    }

    /// The headings that actually divide a document, at whichever level divides it into the most
    /// pieces. A file opening with the book's name and marking its chapters one level down has an
    /// `<h1>` that divides nothing, so the level below it is what the chapters are cut at.
    private static func dividing(_ headings: [Heading], in html: String) -> [Heading]? {
        var best: [Heading]?

        for level in 1 ... 6 {
            let found = headings.filter { $0.level == level }

            guard found.count > (best?.count ?? 0) else { continue }

            // A lone heading at the head of a document names the document rather than dividing it.
            if found.count == 1, let only = found.first, isOpening(only, in: html) { continue }

            best = found
        }

        return best
    }

    private struct Heading {
        let level: Int
        let open: Range<String.Index>
        let close: Range<String.Index>
    }

    /// Every heading in a document, whole, so a piece can be cut from the end of one to the next.
    private static func headings(in html: String) -> [Heading] {
        var found: [Heading] = []
        var cursor = html.startIndex

        while let open = html.range(
            of: "<h[1-6](\\s[^>]*)?>",
            options: [ .regularExpression, .caseInsensitive ],
            range: cursor ..< html.endIndex
        ) {
            // The tag is `<hN`, so the level is the third character of the match.
            let level = html[html.index(open.lowerBound, offsetBy: 2)].wholeNumberValue

            guard
                let level, (1 ... 6).contains(level),
                let close = html.range(
                    of: "</h\(level)\\s*>",
                    options: [ .regularExpression, .caseInsensitive ],
                    range: open.upperBound ..< html.endIndex
                )
            else {
                cursor = open.upperBound
                continue
            }

            found.append(Heading(level: level, open: open, close: close))
            cursor = close.upperBound
        }

        return found
    }

    /// True where nothing but markup stands before this heading, so it names the document itself.
    private static func isOpening(_ heading: Heading, in html: String) -> Bool {
        stripped(html[html.startIndex ..< heading.open.lowerBound]).isEmpty
    }

    /// What a heading calls the piece it opens, or nothing where it is made only of marks.
    private static func named(_ heading: Heading, in html: String) -> String? {
        let words = stripped(html[heading.open.upperBound ..< heading.close.lowerBound])

        return words.contains(where: { $0.isLetter || $0.isNumber }) ? words : nil
    }

    // MARK: - The notes a chapter points at

    /// A chapter with the notes its own text points at written under it.
    ///
    /// A book keeps its notes wherever it likes: beside the text, at the foot of the chapter, or in a
    /// document of its own at the end. Carrying each one down to the chapter that uses it is what lets
    /// a chapter from a file be read exactly the way one from the service is.
    private static func carrying(_ notes: [String: String], into section: ParsedBook.Section) -> ParsedBook.Section {
        guard !notes.isEmpty else { return section }

        var used: [String] = []
        var cursor = section.html.startIndex

        while let mark = section.html.range(of: "href=\"#", range: cursor ..< section.html.endIndex) {
            let rest = section.html[mark.upperBound...]
            let name = String(rest.prefix { $0 != "\"" })

            cursor = mark.upperBound

            if notes[name] != nil, !used.contains(name) { used.append(name) }
        }

        guard !used.isEmpty else { return section }

        let carried = used.map { "<div id=\"\(escaped($0))\">\(escaped(notes[$0] ?? ""))</div>" }

        return ParsedBook.Section(
            title: section.title,
            html: section.html + carried.joined(),
            textLength: section.textLength,
            level: section.level
        )
    }

    // MARK: - Pieces of a document

    private static func made(title: String?, html: String, level: Int) -> ParsedBook.Section {
        ParsedBook.Section(
            title: title?.trimmed.nilWhenEmpty,
            html: html,
            textLength: stripped(html).count,
            level: level
        )
    }

    /// The words of a fragment, with its markup off, for weighing how long a piece runs.
    private static func stripped(_ html: some StringProtocol) -> String {
        String(html)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmed
    }

    private static func escaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Every picture a piece points at, by where it stands in the archive.
    private static func pictures(in html: String) -> [String] {
        var found: [String] = []
        var cursor = html.startIndex

        while let open = html.range(of: "<img", range: cursor ..< html.endIndex) {
            cursor = open.upperBound

            guard
                let source = html.range(of: "src=\"", range: open.upperBound ..< html.endIndex),
                let close = html.range(of: ">", range: open.upperBound ..< html.endIndex),
                source.lowerBound < close.lowerBound
            else { continue }

            found.append(String(html[source.upperBound...].prefix { $0 != "\"" }))
        }

        return found
    }
}
