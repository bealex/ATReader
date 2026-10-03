//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import BookStorage
import Foundation
import Memoirs

/// Saves each new book of a series the reader keeps on author.today to their author.today library.
///
/// A series met for the first time is taken as it stands, so only a book published after that counts
/// as new; a book the reader later takes off the shelf stays seen and isn't put back.
struct SeriesWatch: Sendable {
    private static let memoir = TracedMemoir(label: "series", memoir: AppMemoir.root)
    private static let checkedKey = "series.lastCheckedAt"

    private let client: AuthorTodayClient
    private let store: SQLiteBookStore

    init(client: AuthorTodayClient, store: SQLiteBookStore = .shared) {
        self.client = client
        self.store = store
    }

    /// Looks through every series in `library` once a day, announces what it saved, and answers how many.
    func saveNewBooks(of library: [WorkMetaInfo]) async -> Int {
        guard Self.isDue else { return 0 }

        UserDefaults.standard.set(Date.now, forKey: Self.checkedKey)

        let held = Set(library.map(\.id))
        let seen = await store.seenSeriesBooks()
        var saved: [Int] = []

        for (seriesId, workId) in Self.watched(in: library) {
            guard let listed = try? await client.workDetails(id: workId).seriesWorkIds else { continue }

            let fresh = Self.fresh(listed: listed, held: held, seen: seen[seriesId])

            if !fresh.isEmpty {
                do {
                    try await client.updateLibraryState(workIds: fresh, state: .saved)
                    saved += fresh
                    Self.memoir.info("saved \(safe: fresh.count) new in series \(safe: seriesId)")
                } catch {
                    Self.memoir.error("could not save series \(safe: seriesId): \(error)")
                    continue
                }
            }

            await store.markSeen(workIds: listed, inSeries: seriesId)
        }

        if !saved.isEmpty, let books = try? await client.works(ids: saved) {
            await UpdateNotices.post(newBooks: books)
        }

        return saved.count
    }

    private static var isDue: Bool {
        guard let checked = UserDefaults.standard.object(forKey: checkedKey) as? Date else { return true }

        return Date.now.timeIntervalSince(checked) > BackgroundRefresh.interval
    }

    /// Each series on a shelf the reader keeps, with its latest held book to ask the service about.
    static func watched(in library: [WorkMetaInfo]) -> [Int: Int] {
        let kept = library.filter { work in
            work.seriesId != nil && work.inLibraryState != LibraryState.none && work.inLibraryState != .disliked
        }

        return Dictionary(grouping: kept) { $0.seriesId ?? 0 }
            .compactMapValues { works in works.max { ($0.seriesOrder ?? 0) < ($1.seriesOrder ?? 0) }?.id }
    }

    /// The books a series lists that are neither held nor seen, and none in a series never seen before.
    static func fresh(listed: [Int], held: Set<Int>, seen: Set<Int>?) -> [Int] {
        guard let seen else { return [] }

        return listed.filter { !seen.contains($0) && !held.contains($0) }
    }
}
