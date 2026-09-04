//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import Foundation
import OSLog

/// Turns a file the reader picked into a book the rest of the app can't tell from a fetched one.
///
/// Everything a screen reads comes out of ``LocalStore``, so an imported book only has to fill the same
/// rows a download would: the work, its contents, and one body per chapter. Nothing downstream of that
/// knows the difference.
enum BookImport {
    private static let logger = Logger(subsystem: "com.lonelybytes.atreader", category: "import")

    /// Reads a file and files it as a book, replacing whatever earlier edition of it is already here.
    ///
    /// A book that comes back corrected keeps its id, its place in the library and where the reader had
    /// got to. Its chapters are written again, and the hashes on them are what tells the processor
    /// which ones actually moved.
    @discardableResult
    static func `import`(from url: URL, store: LocalStore = .shared) async throws -> WorkSummary {
        let scoped = url.startAccessingSecurityScopedResource()

        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        guard let data = try? Data(contentsOf: url) else { throw FB2Error.unreadable }

        return try await `import`(source: data, store: store)
    }

    /// Reads a book this device already holds again, for one imported before the parser learned
    /// something it now knows. The file is kept for exactly this.
    @discardableResult
    static func reimport(workId: Int, store: LocalStore = .shared) async throws -> WorkSummary {
        guard let data = LocalBooks.keptFile(workId: workId) else { throw FB2Error.unreadable }

        return try await `import`(source: data, store: store)
    }

    /// The whole of an import, from the bytes of a file to the rows a screen reads.
    private static func `import`(source: Data, store: LocalStore) async throws -> WorkSummary {
        // A book handed out zipped is the common case, so the archive is opened here rather than the
        // reader being asked to unpack it first. What is kept afterwards is the book, not the archive.
        let data = try await unpacked(source)
        let book = try await parse(data)
        let workId = await store.localBookId(fingerprint: book.fingerprint)

        keep(data, workId: workId)
        let cover = write(cover: book.cover, workId: workId)
        let pictures = write(images: book.images, workId: workId)
        let summary = summary(book, workId: workId, coverURL: cover, existing: await store.work(id: workId)?.summary)

        let contents = chapters(book, workId: workId)

        await store.store(work: summary, tags: [])
        await store.store(chapters: contents, workId: workId)
        // A corrected file can be shorter than the one it replaces, and the chapters it dropped would
        // otherwise stay in the contents.
        await store.removeChapters(workId: workId, keeping: contents.map(\.id))

        for (index, section) in book.sections.enumerated() {
            await store.store(
                body: ChapterText(
                    id: LocalBooks.chapterId(workId: workId, index: index),
                    title: section.title,
                    html: named(section.html, pictures: pictures),
                    lastModificationTime: nil
                ),
                workId: workId
            )
        }

        logger.info("imported \(book.sections.count) chapters as work \(workId)")
        return summary
    }

    /// Parsing a book runs to a second on a large file, so it happens away from the main actor.
    private static func parse(_ data: Data) async throws -> FB2Book {
        try await Task.detached(priority: .userInitiated) {
            try FB2Parser.parse(data)
        }.value
    }

    /// The book inside the file, which is the file itself unless it is an archive.
    ///
    /// The bytes decide rather than the name: these arrive called `.fb2.zip`, `.zip` and occasionally
    /// `.fb2` while being an archive all the same.
    private static func unpacked(_ data: Data) async throws -> Data {
        guard ZipArchive.isArchive(data) else { return data }

        return try await Task.detached(priority: .userInitiated) {
            try ZipArchive.book(in: data)
        }.value
    }

    /// Keeps the book's own text so it can be read again without the reader finding the file.
    ///
    /// A failure here costs the re-import button and nothing else, so the import carries on: the book
    /// is already readable by the time this runs.
    private static func keep(_ data: Data, workId: Int) {
        do {
            try LocalBooks.keep(data, workId: workId)
        } catch {
            logger.error("keeping the file failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func chapters(_ book: FB2Book, workId: Int) -> [ChapterInfo] {
        book.sections.enumerated().map { index, section in
            ChapterInfo(
                id: LocalBooks.chapterId(workId: workId, index: index),
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
        _ book: FB2Book,
        workId: Int,
        coverURL: URL?,
        existing: WorkSummary?
    ) -> WorkSummary {
        WorkSummary(
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
        let directory = LocalBooks.imagesDirectory(workId: workId)

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

            result[entry.key] = LocalBooks.imageSource(workId: workId, name: file.lastPathComponent)
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

        let destination = LocalBooks.coverURL(workId: workId)

        do {
            try cover.write(to: destination, options: .atomic)
            return destination
        } catch {
            logger.error("cover write failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Takes an imported book off the device, text and all.
    static func remove(workId: Int, store: LocalStore = .shared) async {
        await store.removeBook(id: workId)
        try? FileManager.default.removeItem(at: LocalBooks.coverURL(workId: workId))
        try? FileManager.default.removeItem(at: LocalBooks.imagesDirectory(workId: workId))
        try? FileManager.default.removeItem(at: LocalBooks.fileURL(workId: workId))
    }
}
