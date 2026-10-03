//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import Foundation
import UserNotifications

/// The alerts for new chapters in the books being read and new books in the reader's series.
enum UpdateNotices {
    /// One alert per book, carrying every chapter it has gained since the reader last opened it.
    static func post(_ result: ChapterUpdateService.Result) async {
        for (workId, title) in result.titlesByWork {
            let count = UpdateBadge.newChapters(for: workId)

            guard count > 0 else { continue }

            await post(
                id: chaptersId(of: workId),
                title: title,
                body: String(localized: "\(count) new chapters"),
                thread: "chapters"
            )
        }
    }

    static func post(newBooks: [CatalogWork]) async {
        for book in newBooks {
            let title =
                book.seriesTitle.map { String(localized: "New book in \($0)") } ?? String(localized: "New book")

            await post(id: "book.\(book.id)", title: title, body: book.title, thread: "books")
        }
    }

    /// Takes a book's chapter alert down once the reader has opened it.
    static func withdrawChapters(of workId: Int) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [ chaptersId(of: workId) ])
    }

    /// Reusing a book's identifier replaces its earlier alert rather than stacking another.
    private static func chaptersId(of workId: Int) -> String { "chapters.\(workId)" }

    private static func post(id: String, title: String, body: String, thread: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = thread

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
