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

        let book = try await parse(data)
        let workId = await store.localBookId(fingerprint: book.fingerprint)
        let cover = write(cover: book.cover, workId: workId)
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
                    html: section.html,
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
    }
}
