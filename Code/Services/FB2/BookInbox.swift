//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

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

    private(set) var errorMessage: String?

    private let store: LocalStore
    private let processor: BookProcessor

    init(store: LocalStore = .shared, processor: BookProcessor = .shared) {
        self.store = store
        self.processor = processor
    }

    func dismissError() { errorMessage = nil }

    /// Reads a book already on the shelf again, from the file kept when it was imported.
    ///
    /// The same path as a file arriving, so the book is re-parsed, re-stored and put back through the
    /// typesetter. It lands on its own row, since the file it came from fingerprints the same way.
    @discardableResult
    func reaccept(workId: Int) async -> WorkSummary? {
        isImporting = true
        errorMessage = nil

        defer { isImporting = false }

        do {
            let work = try await BookImport.reimport(workId: workId, store: store)
            await processor.start(workId: work.id, chapters: store.chapters(workId: work.id))
            importedAt = .now
            return work
        } catch {
            Self.logger.error("re-import failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Reads a file into the library and starts putting it through the typesetter.
    ///
    /// The book is on the shelf and readable as soon as its text is stored. Preparing it runs behind
    /// that, so a long book doesn't hold up whatever asked for it.
    @discardableResult
    func accept(_ url: URL) async -> WorkSummary? {
        isImporting = true
        errorMessage = nil

        defer { isImporting = false }

        do {
            let work = try await BookImport.import(from: url)
            await processor.start(workId: work.id, chapters: store.chapters(workId: work.id))
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
