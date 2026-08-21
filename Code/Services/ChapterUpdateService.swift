//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import Foundation
import UserNotifications

/// Finds chapters published since the last sweep of the reader's "reading" shelf.
///
/// It doubles as the offline warmer: while it is walking the shelf it stores every book and its contents,
/// downloads the chapters it just discovered, and then backfills whatever else is still missing, so a
/// book on the shelf becomes readable without a network.
struct ChapterUpdateService: Sendable {
    /// What one sweep turned up.
    struct Result: Sendable {
        var newChaptersByWork: [Int: Int]
        var titlesByWork: [Int: String]

        var total: Int { newChaptersByWork.values.reduce(0, +) }
    }

    /// How many chapter bodies to download per sweep, so a long absence cannot run away with data.
    /// Newly published chapters come first; the rest of the budget backfills what is still missing.
    static let foregroundChapterBudget = 60
    /// A background window is short and killed when it overruns, so it takes a smaller bite.
    static let backgroundChapterBudget = 15

    private let client: AuthorTodayClient
    private let store: LocalStore

    init(client: AuthorTodayClient, store: LocalStore = .shared) {
        self.client = client
        self.store = store
    }

    /// Walks the reading shelf and reports what is new. Throws only when the shelf itself cannot be read.
    @discardableResult
    func check(chapterBudget: Int = ChapterUpdateService.foregroundChapterBudget) async throws -> Result {
        let library = try await client.fullUserLibrary()
        let works = library.worksInLibrary.map(WorkSummary.init)

        await store.replaceLibrary(with: works)

        let reading = works.filter { $0.libraryState == .reading }
        var counts: [Int: Int] = [:]
        var titles: [Int: String] = [:]
        var budget = chapterBudget

        for work in reading {
            guard let contents = try? await client.workContents(id: work.id) else { continue }

            let fresh = await store.unseenChapters(workId: work.id, in: contents)
            await store.store(chapters: contents, workId: work.id)

            if !fresh.isEmpty {
                counts[work.id] = fresh.count
                titles[work.id] = work.title
            }

            guard budget > 0 else { continue }

            let readable = contents.filter(\.isReadable).sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
            let stored = await store.storedBodyIds(workId: work.id)
            let missing = fresh + readable.map(\.id).filter { !fresh.contains($0) && !stored.contains($0) }

            budget -= await download(chapters: missing.prefix(budget), workId: work.id)
        }

        let result = Result(newChaptersByWork: counts, titlesByWork: titles)
        await UpdateBadge.record(result)
        return result
    }

    /// Downloads chapter bodies, reporting how many actually landed.
    private func download(chapters: some Sequence<Int>, workId: Int) async -> Int {
        var downloaded = 0

        for chapterId in chapters {
            guard await !store.hasBody(workId: workId, chapterId: chapterId) else { continue }
            guard let chapter = try? await client.chapterText(workId: workId, chapterId: chapterId) else { continue }

            await store.store(body: chapter, workId: workId)
            downloaded += 1
        }

        return downloaded
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
