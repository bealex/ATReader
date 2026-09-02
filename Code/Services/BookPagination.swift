//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import CryptoKit
import SwiftUI
import UIKit

/// Where every chapter of a book begins, measured once for one style and one page size.
///
/// A chapter that runs on from the page before it is laid out shorter by however much that page already
/// used, so its page breaks depend on the chapter before it, whose breaks depend on the one before that.
/// Measuring a chapter on its own therefore gives a different answer from measuring it after reading
/// into it, and the text moved under the reader whenever the two disagreed: a chapter opened from the
/// contents started a page of its own, and then jumped up the page as soon as the reader turned back
/// into the chapter before it.
///
/// So the book is measured in one pass, in order from its first chapter, and every chapter keeps the
/// place that pass gave it however the reader arrives at it.
///
/// The pass is kept. Each measurement is filed under the chain hash, which says the book is the same
/// book up to that chapter, and a fingerprint of the setting it was made at. A book reopened unchanged
/// reads its measurements back instead of laying every chapter out again.
@MainActor
final class BookPagination {
    /// Where one chapter sits: how much of its first page the chapter before it already used, and how
    /// many pages it runs to.
    struct Placement: Equatable {
        var startOffset: CGFloat
        var pageCount: Int
    }

    /// How much of a chapter has to reach the page it shares for it to run on at all. A heading with
    /// one or two lines under it reads as a title stranded at the foot of the page.
    static let runOnLineMinimum = 3

    /// A chapter's parsed text, or `nil` where the device doesn't have it.
    typealias ContentProvider = @MainActor (Int) async -> ChapterContent?

    let context: ChapterLayout.Context

    private let workId: Int
    private let store: LocalStore
    /// The setting these measurements were made at, and the only one they are good for.
    private let style: String

    private var placements: [Int: Placement] = [:]

    /// How many chapters from the front have been measured. The pass can stop anywhere and carry on
    /// from here, which is what lets a book be opened before all of it has been measured.
    private(set) var measured = 0

    /// Where the next chapter starts, carried between runs.
    private var startOffset: CGFloat = 0
    /// The last chapter's text folded into every chapter before it, which is what its place depends on.
    private var chain = ""
    /// False once a chapter turns up that can't be hashed. Nothing after it can be keyed either, since
    /// the chain no longer stands for everything that came first.
    private var chained = true

    private init(workId: Int, context: ChapterLayout.Context, store: LocalStore) {
        self.workId = workId
        self.context = context
        self.store = store
        self.style = context.fingerprint
    }

    /// A book with nothing measured yet.
    static func make(workId: Int, context: ChapterLayout.Context, store: LocalStore = .shared) -> BookPagination {
        BookPagination(workId: workId, context: context, store: store)
    }

    /// True once every chapter has a place.
    func hasMeasuredEverything(of chapters: [ChapterInfo]) -> Bool { measured >= chapters.count }

    /// Measures chapters in order until `count` of them are done, carrying on from wherever the last
    /// run stopped.
    ///
    /// Only text the device already holds is measured. Fetching a whole book to find out where its pages
    /// fall would turn opening one chapter into a download of all of them, so a chapter that isn't here
    /// yet ends the run-on instead and the chapter after it starts a page of its own.
    ///
    /// A chapter's place depends on every chapter before it and on none of the ones after, so a prefix
    /// is enough to put the reader on a page and the rest can follow behind them.
    func measure(
        chapters: [ChapterInfo],
        through count: Int,
        content: ContentProvider,
        onProgress: (@MainActor (Double) -> Void)? = nil
    ) async {
        guard context.isUsable else { return }

        let target = min(count, chapters.count)

        while measured < target {
            let index = measured
            let chapter = chapters[index]

            guard !Task.isCancelled else { return }

            defer {
                measured = index + 1
                onProgress?(Double(index + 1) / Double(target))
            }

            // A chapter's hash is one small read and its prepared text is a large one, so the
            // measurement is looked for first. A book reopened unchanged never loads its own text.
            let hash = await store.contentHash(workId: workId, chapterId: chapter.id)
            let known = chained ? hash.map { Self.folded(chain, $0) } : nil

            if let known, let cached = await stored(chapter.id, chain: known) {
                chain = known
                placements[chapter.id] = Placement(startOffset: cached.startOffset, pageCount: cached.pageCount)
                startOffset = cached.nextOffset
                continue
            }

            guard
                let text = await content(chapter.id)
            else {
                placements[chapter.id] = Placement(startOffset: startOffset, pageCount: 0)
                startOffset = 0
                chained = false
                continue
            }

            chained = await fold(chapterId: chapter.id, known: hash, chained: chained)
            startOffset = await layOut(
                chapter,
                position: index + 1,
                text: text,
                from: startOffset,
                key: chained ? chain : nil
            )
        }
    }

    /// Folds a chapter into the chain once its text has been through the typesetter, which is what
    /// writes the hash a book being measured for the first time doesn't have yet.
    private func fold(chapterId: Int, known: String?, chained: Bool) async -> Bool {
        let settled: String?

        if let known {
            settled = known
        } else {
            settled = await store.contentHash(workId: workId, chapterId: chapterId)
        }

        guard chained, let settled else { return false }

        chain = Self.folded(chain, settled)
        return true
    }

    private func stored(_ chapterId: Int, chain: String) async -> LocalStore.StoredPlacement? {
        await store.placement(workId: workId, chapterId: chapterId, chain: chain, style: style)
    }

    /// Lays one chapter out to find how far it runs, files the answer where a later run will find it,
    /// and reports where the chapter after it begins.
    ///
    /// The layout itself is thrown away: all this pass keeps is where the chapter starts and how far it
    /// runs, so a book of any length costs one chapter's memory at a time.
    private func layOut(
        _ chapter: ChapterInfo,
        position: Int,
        text: ChapterContent,
        from startOffset: CGFloat,
        key: String?
    ) async -> CGFloat {
        let heading = ChapterHeading.make(position: position, title: chapter.title)
        var offset = startOffset
        var layout = await ChapterLayout.make(
            chapterId: chapter.id,
            content: text,
            heading: heading,
            context: context,
            startOffset: offset
        )

        // The free space was measured before the heading was set into it, and a heading stands far
        // taller than the lines that measured it. So the answer is read back from the page instead: a
        // chapter that could not bring a few lines of itself onto the page it shares leaves its title
        // stranded at the foot, and takes a page of its own instead.
        if offset > 0, layout.bodyLineCount(onPage: 0) < Self.runOnLineMinimum {
            offset = 0
            layout = await ChapterLayout.make(
                chapterId: chapter.id,
                content: text,
                heading: heading,
                context: context,
                startOffset: 0
            )
        }

        let next = Self.startOffset(after: layout, context: context)

        placements[chapter.id] = Placement(startOffset: offset, pageCount: layout.pageCount)

        if let key {
            await store.store(
                placement: .init(startOffset: offset, pageCount: layout.pageCount, nextOffset: next),
                workId: workId,
                chapterId: chapter.id,
                chain: key,
                style: style
            )
        }

        return next
    }

    /// One chapter's text folded into everything before it.
    private static func folded(_ chain: String, _ hash: String) -> String {
        SHA256.hash(data: Data((chain + hash).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func placement(of chapterId: Int) -> Placement? { placements[chapterId] }

    /// How far down its first page a chapter begins. Zero where it starts a page of its own.
    func startOffset(of chapterId: Int) -> CGFloat { placements[chapterId]?.startOffset ?? 0 }

    /// True when this chapter begins part-way down the page the one before it ended on.
    func runsOn(_ chapterId: Int) -> Bool { startOffset(of: chapterId) > 0 }

    /// Where a chapter starts on the page the one before it ended on, and how far down.
    ///
    /// A chapter only runs on when what is left of the page holds a decent piece of it; a heading with
    /// two lines under it belongs on the next page instead.
    static func startOffset(after previous: ChapterLayout, context: ChapterLayout.Context) -> CGFloat {
        let chapterGap = context.style.fontSize * 2.5
        let lineHeight = context.style.fontSize + context.style.lineSpacing
        let free = previous.tailFreeSpace - chapterGap

        guard free >= max(lineHeight * 6, context.textSize.height * 0.25) else { return 0 }

        return context.textSize.height - previous.tailFreeSpace + chapterGap
    }
}
