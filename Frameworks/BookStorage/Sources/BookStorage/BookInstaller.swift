//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Foundation
import OSLog

/// Puts a book a parser has read onto this device: its file, its cover, its pictures and its rows.
///
/// Knows nothing about any file format. Whoever hands it a ``ParsedBook`` has already decided what
/// could read one.
public enum BookInstaller {
    private static let logger = Logger(subsystem: "com.lonelybytes.atreader", category: "install")

    /// Files a parsed book against the number its fingerprint already has, or a new one.
    ///
    /// `source` is the book's own text, kept so it can be read again by a parser that has since
    /// learned something.
    @discardableResult
    public static func install(
        _ book: ParsedBook,
        source: Data,
        store: SQLiteBookStore = .shared
    ) async -> Book {
        let workId = await store.localBookId(fingerprint: book.fingerprint)

        keep(source, workId: workId)
        let cover = write(cover: book.cover, workId: workId)
        let pictures = write(images: book.images, workId: workId)
        let summary = summary(book, workId: workId, coverURL: cover, existing: await store.book(id: workId)?.summary)

        let contents = chapters(book, workId: workId)

        await store.store(book: summary, tags: [])
        await store.store(chapters: contents, workId: workId)
        // A corrected file can be shorter than the one it replaces, and the chapters it dropped would
        // otherwise stay in the contents.
        await store.removeChapters(workId: workId, keeping: contents.map(\.id))

        for (index, section) in book.sections.enumerated() {
            await store.store(
                body: ChapterBody(
                    id: BookNumbering.chapterId(workId: workId, index: index),
                    title: section.title,
                    html: named(section.html, pictures: pictures),
                    lastModificationTime: nil
                ),
                workId: workId
            )
        }

        logger.info("installed \(book.sections.count) chapters as work \(workId)")
        return summary
    }

    /// Keeps the book's own text so it can be read again without the reader finding the file.
    ///
    /// A failure here costs the re-import button and nothing else, so the import carries on: the book
    /// is already readable by the time this runs.
    private static func keep(_ data: Data, workId: Int) {
        do {
            try LocalBookFiles.keep(data, workId: workId)
        } catch {
            logger.error("keeping the file failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func chapters(_ book: ParsedBook, workId: Int) -> [BookChapter] {
        book.sections.enumerated().map { index, section in
            BookChapter(
                id: BookNumbering.chapterId(workId: workId, index: index),
                workId: workId,
                title: section.title,
                sortOrder: index,
                textLength: section.textLength
            )
        }
    }

    /// The book as a library row.
    ///
    /// A file is finished by definition: nobody is going to publish another chapter of it here. The
    /// shelf is set so the library lists it, and the reading progress the device already had is left
    /// where it is, since a corrected file is the same book at the same page.
    private static func summary(
        _ book: ParsedBook,
        workId: Int,
        coverURL: URL?,
        existing: Book?
    ) -> Book {
        Book(
            id: workId,
            title: book.title,
            authorLine: book.authorLine,
            coverURL: coverURL,
            annotation: book.annotation,
            seriesTitle: book.series,
            seriesOrder: book.seriesOrder,
            textLength: book.sections.reduce(0) { $0 + $1.textLength },
            likeCount: nil,
            isFinished: true,
            status: nil,
            isPurchased: nil,
            adultOnly: nil,
            lastUpdateTime: .now,
            readingProgress: existing?.readingProgress,
            hasStartedReading: existing?.hasStartedReading ?? false,
            lastReadTime: existing?.lastReadTime,
            lastChapterId: existing?.lastChapterId,
            libraryState: existing?.libraryState ?? .reading
        )
    }

    /// Writes the book's pictures out beside it, and reports the source each one now answers to.
    ///
    /// A picture is a file rather than bytes in the database: a chapter body is read on every
    /// re-pagination, and a megabyte of base64 riding along with it would be read every time.
    private static func write(images: [String: Data], workId: Int) -> [String: String] {
        let directory = LocalBookFiles.imagesDirectory(workId: workId)

        // A corrected file may drop pictures the one it replaces had.
        try? FileManager.default.removeItem(at: directory)

        guard !images.isEmpty else { return [:] }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("image directory failed: \(error.localizedDescription, privacy: .public)")
            return [:]
        }

        return images.reduce(into: [String: String]()) { result, entry in
            let file = directory.appendingPathComponent(entry.key.replacingOccurrences(of: "/", with: "_"))

            guard (try? entry.value.write(to: file, options: .atomic)) != nil else { return }

            result[entry.key] = LocalBookFiles.imageSource(workId: workId, name: file.lastPathComponent)
        }
    }

    /// Points every `<img>` in a section at the file its picture was written to.
    ///
    /// The parser names a picture the way the file does, which says nothing about where it landed. One
    /// the reader has no file for is dropped rather than left as a gap on the page.
    private static func named(_ html: String, pictures: [String: String]) -> String {
        guard html.contains("<img") else { return html }

        return html.replacing(/<img src="([^"]*)">/) { match in
            pictures[String(match.1)].map { "<img src=\"\($0)\">" } ?? ""
        }
    }

    private static func write(cover: Data?, workId: Int) -> URL? {
        guard let cover, !cover.isEmpty else { return nil }

        let destination = LocalBookFiles.coverURL(workId: workId)

        do {
            try cover.write(to: destination, options: .atomic)
            return destination
        } catch {
            logger.error("cover write failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Takes an imported book off the device, text and all.
    public static func remove(workId: Int, store: SQLiteBookStore = .shared) async {
        await store.removeBook(id: workId)
        try? FileManager.default.removeItem(at: LocalBookFiles.coverURL(workId: workId))
        try? FileManager.default.removeItem(at: LocalBookFiles.imagesDirectory(workId: workId))
        try? FileManager.default.removeItem(at: LocalBookFiles.fileURL(workId: workId))
    }
}
