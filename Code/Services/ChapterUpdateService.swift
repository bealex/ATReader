//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import Foundation
import UserNotifications

/// Finds chapters published since the last sweep of the reader's "reading" shelf.
///
/// It doubles as the offline-cache warmer: while it is walking the shelf it stores each table of contents
/// and pulls the bodies of the chapters it just discovered, so new material is readable without a network.
struct ChapterUpdateService: Sendable {
    /// What one sweep turned up.
    struct Result: Sendable {
        var newChaptersByWork: [Int: Int]
        var titlesByWork: [Int: String]

        var total: Int { newChaptersByWork.values.reduce(0, +) }
    }

    /// How many freshly found chapters to download per sweep, so a long absence cannot run away with data.
    static let chapterPrefetchLimit = 25

    private let client: AuthorTodayClient
    private let cache: BookCache

    init(client: AuthorTodayClient, cache: BookCache = .shared) {
        self.client = client
        self.cache = cache
    }

    /// Walks the reading shelf and reports what is new. Throws only when the shelf itself cannot be read.
    @discardableResult
    func check(prefetchBodies: Bool = true) async throws -> Result {
        let library = try await client.userLibrary(page: 1, pageSize: 200)
        let reading = library.worksInLibrary.filter { $0.inLibraryState == .reading }

        await cache.store(readingShelf: reading)
        await cache.retainOnly(workIds: Set(reading.map(\.id)))

        var snapshots = await cache.snapshots()
        var counts: [Int: Int] = [:]
        var titles: [Int: String] = [:]
        var prefetched = 0

        for work in reading {
            guard let contents = try? await client.workContents(id: work.id) else { continue }

            let readable = contents.filter(\.isReadable).sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
            let ids = readable.map(\.id)

            await cache.store(contents: contents, workId: work.id)

            // The first sweep only records a baseline — everything already published is not "new".
            guard
                let previous = snapshots[work.id]
            else {
                snapshots[work.id] = BookCache.Snapshot(chapterIds: ids, checkedAt: .now, title: work.title)
                continue
            }

            let fresh = previous.newChapters(against: ids)

            if !fresh.isEmpty {
                counts[work.id] = fresh.count
                titles[work.id] = work.title
            }

            if prefetchBodies {
                for chapterId in fresh where prefetched < Self.chapterPrefetchLimit {
                    guard await !cache.hasChapter(workId: work.id, chapterId: chapterId) else { continue }
                    guard
                        let chapter = try? await client.chapterText(workId: work.id, chapterId: chapterId)
                    else { continue }

                    await cache.store(chapter: chapter, workId: work.id)
                    prefetched += 1
                }
            }

            snapshots[work.id] = BookCache.Snapshot(chapterIds: ids, checkedAt: .now, title: work.title)
        }

        await cache.store(snapshots: snapshots)

        let result = Result(newChaptersByWork: counts, titlesByWork: titles)
        await UpdateBadge.record(result)
        return result
    }
}

/// The app-icon badge and the per-book counts the library screen shows.
///
/// Kept in user defaults rather than the cache so the UI can read it synchronously while drawing.
enum UpdateBadge {
    private static let countsKey = "updates.newChaptersByWork"
    private static let checkedKey = "updates.lastCheckedAt"

    static var newChaptersByWork: [Int: Int] {
        let raw = UserDefaults.standard.dictionary(forKey: countsKey) as? [String: Int] ?? [:]
        return Dictionary(
            raw.compactMap { key, value in Int(key).map { ($0, value) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    static var total: Int { newChaptersByWork.values.reduce(0, +) }

    static var lastCheckedAt: Date? {
        UserDefaults.standard.object(forKey: checkedKey) as? Date
    }

    static func newChapters(for workId: Int) -> Int { newChaptersByWork[workId] ?? 0 }

    static func record(_ result: ChapterUpdateService.Result) async {
        let merged = newChaptersByWork.merging(result.newChaptersByWork, uniquingKeysWith: +)
        write(merged)
        await applyBadge()
    }

    /// Called once the reader opens a book, so its chapters stop counting as unseen.
    static func clear(workId: Int) async {
        var counts = newChaptersByWork
        counts.removeValue(forKey: workId)
        write(counts)
        await applyBadge()
    }

    static func clearAll() async {
        write([:])
        await applyBadge()
    }

    private static func write(_ counts: [Int: Int]) {
        let raw = Dictionary(
            counts.filter { $0.value > 0 }.map { (String($0.key), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        UserDefaults.standard.set(raw, forKey: countsKey)
        UserDefaults.standard.set(Date.now, forKey: checkedKey)
    }

    private static func applyBadge() async {
        try? await UNUserNotificationCenter.current().setBadgeCount(total)
    }

    /// The badge needs the notification permission even though the app posts no alerts.
    static func requestBadgePermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [ .badge ])
    }
}
