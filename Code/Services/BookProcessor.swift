//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import CryptoKit
import Foundation
import OSLog

/// Puts a book through the typesetter once and keeps the result, so opening it again costs a read
/// rather than the work.
///
/// Binding the words a line may not break between and marking every hyphenation point costs about as
/// much as laying the book out, and neither depends on the font, the margins or the size. So it is done
/// once per chapter and stored. A 400,000-character book is a few seconds of work the first time and
/// none of it afterwards.
///
/// The walk runs behind the reader rather than in front of it. A book opens on its first chapter as
/// soon as that one chapter is ready, and the rest arrive while it is being read.
actor BookProcessor {
    static let shared = BookProcessor()

    private static let logger = Logger(subsystem: "com.lonelybytes.atreader", category: "processor")

    /// How far a book has been through the typesetter.
    struct Progress: Sendable, Equatable {
        let prepared: Int
        let total: Int

        var fraction: Double { total > 0 ? Double(prepared) / Double(total) : 1 }
        var isComplete: Bool { prepared >= total }
    }

    private let store: LocalStore
    private var walks: [Int: Task<Void, Never>] = [:]
    private var progress: [Int: Progress] = [:]

    init(store: LocalStore = .shared) {
        self.store = store
    }

    func progress(of workId: Int) -> Progress? { progress[workId] }

    // MARK: - One chapter, now

    /// A chapter's prepared text, from the store where it is still good and made here where it isn't.
    ///
    /// This is the reader's way in, and it never waits for the rest of the book. The chain is left
    /// empty because only a walk in order can know it, and ``process(workId:chapters:)`` fills it in.
    func content(workId: Int, chapterId: Int) async -> ChapterContent? {
        guard let body = await store.body(workId: workId, chapterId: chapterId) else { return nil }

        let hash = Self.hash(body.html)

        if let cached = await store.preparedChapter(workId: workId, chapterId: chapterId, contentHash: hash) {
            return cached.content
        }

        let prepared = await ChapterContent.prepare(html: body.html)

        await store.store(
            prepared: .init(chapterId: chapterId, contentHash: hash, chainHash: "", content: prepared),
            workId: workId
        )
        return prepared
    }

    // MARK: - The whole book, behind the reader

    /// Prepares everything in a book that isn't prepared already, in order, once at a time.
    ///
    /// A second call while one is running joins it rather than starting another.
    func start(workId: Int, chapters: [ChapterInfo]) {
        guard walks[workId] == nil else { return }

        let readable = chapters.filter(\.isReadable)

        guard !readable.isEmpty else { return }

        walks[workId] = Task(priority: .utility) { [weak self] in
            await self?.process(workId: workId, chapters: readable)
            await self?.finish(workId: workId)
        }
    }

    func stop(workId: Int) {
        walks[workId]?.cancel()
        walks[workId] = nil
    }

    private func finish(workId: Int) {
        walks[workId] = nil
    }

    /// Walks the book from its first chapter, preparing what has moved and leaving what hasn't.
    ///
    /// Each chapter carries its own text's hash and that hash folded into every chapter before it. The
    /// first differs when a chapter's own text has changed and is what decides whether it must be set
    /// again; the second differs from there on to the end of the book, and is what says the book's shape
    /// has moved even where a later chapter's own words have not. Storing both is what lets a corrected
    /// file re-use every chapter it didn't touch.
    private func process(workId: Int, chapters: [ChapterInfo]) async {
        var chain = ""
        var done = 0

        progress[workId] = Progress(prepared: 0, total: chapters.count)

        for chapter in chapters {
            guard !Task.isCancelled else { return }

            defer {
                done += 1
                progress[workId] = Progress(prepared: done, total: chapters.count)
            }

            guard let body = await store.body(workId: workId, chapterId: chapter.id) else { continue }

            let contentHash = Self.hash(body.html)
            let chainHash = Self.hash(chain + contentHash)
            let cached = await store.preparedChapter(workId: workId, chapterId: chapter.id, contentHash: contentHash)

            chain = chainHash

            // Prepared, and standing in the same place in the book as when it was prepared.
            if cached?.chainHash == chainHash { continue }

            // The text is reused whenever the chapter's own words are unchanged: only its place in the
            // book moved, and the chain is what records that.
            let content =
                if let existing = cached?.content { existing } else { await ChapterContent.prepare(html: body.html) }

            await store.store(
                prepared: .init(
                    chapterId: chapter.id,
                    contentHash: contentHash,
                    chainHash: chainHash,
                    content: content
                ),
                workId: workId
            )

            // A yield between chapters, so a book being prepared never holds up a page turn.
            await Task.yield()
        }

        Self.logger.info("prepared \(done) chapters of work \(workId)")
    }

    /// A chapter's source, hashed together with the rules that will be applied to it.
    ///
    /// Both go in because what is stored is the output of one on the other. Hashing the source alone
    /// left a book that had already been prepared holding text an older typesetter made, with nothing
    /// in the source to say it was stale.
    private static func hash(_ text: String) -> String {
        SHA256.hash(data: Data("\(Typography.version)\u{1}\(text)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
