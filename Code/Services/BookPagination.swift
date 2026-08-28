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
@MainActor
final class BookPagination {
    /// Where one chapter sits: how much of its first page the chapter before it already used, and how
    /// many pages it runs to.
    struct Placement: Equatable {
        var startOffset: CGFloat
        var pageCount: Int
    }

    /// A chapter's parsed text, or `nil` where the device doesn't have it.
    typealias ContentProvider = @MainActor (Int) async -> ChapterContent?

    let context: ChapterLayout.Context

    private var placements: [Int: Placement] = [:]

    private init(context: ChapterLayout.Context) {
        self.context = context
    }

    /// Measures every chapter in order.
    ///
    /// Only text the device already holds is measured. Fetching a whole book to find out where its pages
    /// fall would turn opening one chapter into a download of all of them, so a chapter that isn't here
    /// yet ends the run-on instead and the chapter after it starts a page of its own.
    static func make(
        workId: Int,
        chapters: [ChapterInfo],
        context: ChapterLayout.Context,
        content: ContentProvider,
        store: LocalStore = .shared,
        onProgress: (@MainActor (Double) -> Void)? = nil
    ) async -> BookPagination {
        let pagination = BookPagination(context: context)

        guard context.isUsable, !chapters.isEmpty else { return pagination }

        let style = context.fingerprint
        var startOffset: CGFloat = 0
        /// This chapter's text folded into every chapter before it, which is exactly what its place in
        /// the book depends on.
        var chain = ""
        /// False once a chapter turns up that can't be hashed. Nothing after it can be keyed either,
        /// since the chain no longer stands for everything that came first.
        var chained = true

        for (index, chapter) in chapters.enumerated() {
            guard !Task.isCancelled else { break }

            defer { onProgress?(Double(index + 1) / Double(chapters.count)) }

            // A chapter's hash is one small read and its prepared text is a large one, so the
            // measurement is looked for first. A book reopened unchanged never loads its own text.
            let hash = await store.contentHash(workId: workId, chapterId: chapter.id)

            let known = chained ? hash.map { Self.folded(chain, $0) } : nil

            if
                let known,
                let cached = await store.placement(
                    workId: workId,
                    chapterId: chapter.id,
                    chain: known,
                    style: style
                )
            {
                chain = known
                pagination.placements[chapter.id] = Placement(
                    startOffset: cached.startOffset,
                    pageCount: cached.pageCount
                )
                startOffset = cached.nextOffset
                continue
            }

            guard
                let text = await content(chapter.id)
            else {
                pagination.placements[chapter.id] = Placement(startOffset: startOffset, pageCount: 0)
                startOffset = 0
                chained = false
                continue
            }

            // Preparing a chapter is what writes its hash, so a book measured for the first time only
            // has one to fold in once its text has been through the typesetter.
            let settled: String?

            if let hash {
                settled = hash
            } else {
                settled = await store.contentHash(workId: workId, chapterId: chapter.id)
            }

            if chained, let settled {
                chain = Self.folded(chain, settled)
            } else {
                // Nothing after an unhashable chapter can be keyed either: the chain no longer stands
                // for everything that came before it.
                chained = false
            }

            let key = chained ? chain : nil

            // The layout itself is thrown away: all this pass keeps is where the chapter starts and how
            // far it runs, so a book of any length costs one chapter's memory at a time.
            let layout = await ChapterLayout.make(
                chapterId: chapter.id,
                content: text,
                heading: ChapterHeading.make(position: index + 1, title: chapter.title),
                context: context,
                startOffset: startOffset
            )
            let next = Self.startOffset(after: layout, context: context)

            pagination.placements[chapter.id] = Placement(startOffset: startOffset, pageCount: layout.pageCount)

            if let key {
                await store.store(
                    placement: .init(startOffset: startOffset, pageCount: layout.pageCount, nextOffset: next),
                    workId: workId,
                    chapterId: chapter.id,
                    chain: key,
                    style: style
                )
            }

            startOffset = next
        }

        return pagination
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
    private static func startOffset(after previous: ChapterLayout, context: ChapterLayout.Context) -> CGFloat {
        guard previous.pageCount > 1 else { return 0 }

        let chapterGap = context.style.fontSize * 2.5
        let lineHeight = context.style.fontSize + context.style.lineSpacing
        let free = previous.tailFreeSpace - chapterGap

        guard free >= max(lineHeight * 6, context.textSize.height * 0.25) else { return 0 }

        return context.textSize.height - previous.tailFreeSpace + chapterGap
    }
}
