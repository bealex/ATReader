//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookFormats
import BookKit
import BookRenderer
import BookStorage
import Foundation
import OSLog

/// Every way a book gets into the library, in one place.
///
/// A file arrives either because the reader picked it or because another app handed it over, and both
/// have to do the same three things: read it in, start preparing it, and tell whatever is on screen
/// that the shelf has changed. Opening a file can also happen while the library screen doesn't exist
/// yet, so the work can't live there.
@Observable @MainActor
final class BookInbox {
    static let shared = BookInbox()

    private static let logger = Logger(subsystem: "com.lonelybytes.atreader", category: "import")

    /// True while a file is being read in.
    private(set) var isImporting = false

    /// Moves every time a book lands, so a screen showing the shelf knows to read it again.
    private(set) var importedAt: Date?

    /// The last book read in, so a shelf that wasn't the one to ask for it can still follow it
    /// through the typesetter rather than only redrawing once.
    private(set) var lastAccepted: Int?

    private(set) var errorMessage: String?

    /// Says the shelf has changed, for a part of the app that changed it without coming through here.
    ///
    /// A synchronisation writes straight to the store, and a screen showing the shelf has no other way
    /// to learn that its books have moved under it. No book landed, so the last one to land is cleared:
    /// a shelf told otherwise would follow a book it has already taken in instead of reading the store.
    func libraryChanged() {
        lastAccepted = nil
        importedAt = .now
    }

    private let store: SQLiteBookStore
    private let processor: BookProcessor

    init(store: SQLiteBookStore = .shared, processor: BookProcessor = .shared) {
        self.store = store
        self.processor = processor
    }

    func dismissError() { errorMessage = nil }

    /// Reads a book already on the shelf again, from the file kept when it was imported.
    ///
    /// The same path as a file arriving, so the book is re-parsed, re-stored and put back through the
    /// typesetter. It lands on its own row, since the file it came from fingerprints the same way.
    @discardableResult
    func reaccept(workId: Int) async -> Book? {
        isImporting = true
        errorMessage = nil

        defer { isImporting = false }

        do {
            let work = try await BookImporting.reimport(workId: workId, store: store)
            await processor.start(workId: work.id, chapters: store.chapters(workId: work.id))
            importedAt = .now
            return work
        } catch {
            Self.logger.error("re-import failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Reads again every book whose text this build would now make something different of.
    ///
    /// What a chapter holds is whatever the parser made of the file when it was read, so a parser that
    /// has learned something reaches the books already on the shelf only by reading their files again.
    /// This is what saves the reader doing it a book at a time; see ``BookReading``.
    ///
    /// One at a time and off the main thread, because a whole library can be behind at once and none of
    /// it is urgent. A book whose file this device no longer has is left as it is, and one that fails to
    /// read keeps its old version, so the next run tries it again.
    @discardableResult
    func rereadWhatIsBehind() async -> Int {
        let behind = await store.localBooks()
            .filter { $0.isBehindThisBuild && LocalBookFiles.hasKeptFile(workId: $0.workId) }
            .sorted { $0.workId > $1.workId }

        guard !behind.isEmpty else { return 0 }

        Self.logger.info("reading \(behind.count) books again for this build")

        var read = 0

        for record in behind {
            do {
                let work = try await BookImporting.reimport(workId: record.workId, store: store)

                await processor.start(workId: work.id, chapters: store.chapters(workId: work.id))
                read += 1
            } catch {
                Self.logger.error(
                    "reading \(record.workId) again failed: \(error.localizedDescription, privacy: .public)"
                )
            }

            await Task.yield()
        }

        if read > 0 { libraryChanged() }

        Self.logger.info("read \(read) of \(behind.count) books again")
        return read
    }

    /// Reads a file into the library and starts putting it through the typesetter.
    ///
    /// The book is on the shelf and readable as soon as its text is stored. Preparing it runs behind
    /// that, so a long book doesn't hold up whatever asked for it.
    @discardableResult
    func accept(_ url: URL) async -> Book? {
        isImporting = true
        errorMessage = nil

        defer { isImporting = false }

        do {
            let work = try await BookImporting.import(from: url, store: store)
            await processor.start(workId: work.id, chapters: store.chapters(workId: work.id))
            lastAccepted = work.id
            importedAt = .now
            return work
        } catch {
            Self.logger.error("import failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func accept(_ urls: [URL]) async {
        for url in urls { await accept(url) }
    }
}
