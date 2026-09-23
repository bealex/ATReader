//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import BackgroundTasks
import Foundation

/// Schedules the once-a-day sweep for new chapters.
///
/// The system decides when a refresh actually runs; `earliestBeginDate` only sets the floor. Each run
/// re-submits the next request, so the chain keeps going as long as the reader opens the app now and then.
enum BackgroundRefresh {
    static let taskIdentifier = "com.lonelybytes.atreader.refresh"

    static let interval: TimeInterval = 24 * 60 * 60

    static func scheduleNext(after delay: TimeInterval = interval) {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: delay)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Submission fails on the simulator and when the app is not permitted to refresh; the
            // foreground sweep still keeps the badge current, so this is not worth surfacing.
        }
    }

    /// The work one refresh does: look for new chapters, warm the cache, update the badge.
    static func runSweep(session: SessionStore) async {
        scheduleNext()

        guard let client = await signedInClient(of: session) else { return }

        _ = try? await ChapterUpdateService(client: client)
            .check(chapterBudget: ChapterUpdateService.backgroundChapterBudget)
    }

    /// A launch straight into the background builds no view, so nothing else has restored the session.
    @MainActor
    private static func signedInClient(of session: SessionStore) async -> AuthorTodayClient? {
        if case .restoring = session.state { await session.restore() }

        return session.isSignedIn ? session.client : nil
    }
}
