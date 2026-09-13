//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Foundation
import UniformTypeIdentifiers

/// Reading a book out of an EPUB file.
///
/// The format gives away what FB2 makes a parser infer: the spine says what order the book reads in and
/// the navigation says what each piece is called. What it asks for in return is the reduction in
/// ``EpubContent``, since its chapters are arbitrary XHTML where FB2's are a small vocabulary.
public struct EpubFormat: BookFormat {
    public init() {}

    /// What a picker offers when it is asking for a book of this format.
    public static var contentTypes: [UTType] {
        [ UTType("org.idpf.epub-container"), UTType(filenameExtension: "epub") ].compactMap { $0 }
    }

    /// An archive carrying the container every EPUB opens with. The bytes decide, not the name.
    public func canRead(_ data: Data) -> Bool {
        guard ZipArchive.isArchive(data) else { return false }

        return (try? ZipReader(data))?.has("META-INF/container.xml") ?? false
    }

    public func read(_ data: Data) async throws -> ReadBook {
        let book = try await Task.detached(priority: .userInitiated) {
            try Self.parse(data)
        }.value

        // The file as it arrived: an EPUB is an archive by definition, so there is nothing to unpack
        // it into that a second reading would rather have.
        return ReadBook(book: book, source: data)
    }

    static func parse(_ data: Data) throws -> ParsedBook {
        let archive = try ZipReader(data)
        let package = try EpubPackage.read(from: archive)

        guard !package.isFixedLayout else { throw BookFileError.fixedLayout }

        let styles = EpubStyles.read(package, from: archive)
        let navigation = EpubNavigation.read(package, from: archive)
        var read: [(item: EpubPackage.Item, content: EpubContent)] = []

        for item in package.spine where item.isDocument {
            // The navigation document is the book's contents rather than a chapter of it, and the app
            // draws a contents of its own from what comes out of here.
            guard item.path != package.navigation?.path, let text = archive.text(named: item.path) else { continue }

            read.append((
                item,
                EpubContent.read(
                    Markup.parse(text),
                    path: item.path,
                    styles: styles,
                    readsRightToLeft: package.readsRightToLeft,
                    divisions: Set(navigation.entries(forPath: item.path).compactMap(\.fragment))
                )
            ))
        }

        let sections = EpubSections.make(
            read,
            navigation: navigation,
            notes: notes(in: read),
            coverPath: package.cover?.path,
            bookTitle: package.title
        )

        guard !sections.isEmpty else { throw BookFileError.notABook }

        return ParsedBook(
            title: package.title?.trimmed.nilWhenEmpty ?? String(localized: "Untitled"),
            authors: package.authors,
            annotation: package.annotation,
            language: package.language?.trimmed,
            series: package.series?.trimmed.nilWhenEmpty,
            seriesOrder: package.seriesOrder,
            cover: cover(package, read: read, from: archive),
            images: pictures(in: read, from: archive),
            sections: sections,
            identifier: package.identifier,
            format: "epub"
        )
    }

    /// Every note the book holds, wherever in it the note stands.
    ///
    /// A file keeps its notes beside the text that points at them, at the end of the chapter, or in a
    /// document of its own after every chapter. All three read the same once the whole book has been
    /// through the reduction, which is why the notes are gathered before any chapter is made.
    private static func notes(in read: [(item: EpubPackage.Item, content: EpubContent)]) -> [String: String] {
        read.reduce(into: [String: String]()) { result, each in
            result.merge(each.content.marked) { first, _ in first }
        }
    }

    private static func pictures(
        in read: [(item: EpubPackage.Item, content: EpubContent)],
        from archive: ZipReader
    ) -> [String: Data] {
        let wanted = read.reduce(into: Set<String>()) { $0.formUnion($1.content.pictures) }

        return wanted.reduce(into: [String: Data]()) { result, path in
            result[path] = archive.member(named: path)
        }
    }

    /// The book's cover: the one its package names, or the picture its first page turns out to be.
    ///
    /// The fallback is worth having because a book whose opening page is nothing but a plate has a
    /// cover whether or not anything in its metadata says so.
    private static func cover(
        _ package: EpubPackage,
        read: [(item: EpubPackage.Item, content: EpubContent)],
        from archive: ZipReader
    ) -> Data? {
        if let named = package.cover, let data = archive.member(named: named.path) { return data }

        guard
            let opening = read.first,
            opening.content.textLength == 0,
            let picture = opening.content.pictures.first
        else { return nil }

        return archive.member(named: picture)
    }
}
