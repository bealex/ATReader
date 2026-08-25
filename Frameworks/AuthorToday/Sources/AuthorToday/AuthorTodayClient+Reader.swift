//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

extension AuthorTodayClient {
    /// Opens a reading session and reports where the reader left off.
    public func startReading(workId: Int, chapterId: Int) async throws -> ReaderStats {
        try await send(Endpoint(path: "/v1/reader/start/\(workId)/\(chapterId)"))
    }

    /// The positions the service holds, changed since `date`.
    ///
    /// This is the read half of the position sync. The service records nothing this client sends, but
    /// it does record what its own site does, so this is how reading done elsewhere gets here.
    public func readingProgress(since date: Date) async throws -> [ReadingProgressInfo] {
        guard credentials.isAuthenticated else { throw AuthorTodayError.notAuthenticated }

        let formatter = ISO8601DateFormatter()
        let endpoint = Endpoint(
            path: "/v1/account/reading-progress",
            query: [ URLQueryItem(name: "lastSyncTime", value: formatter.string(from: date)) ]
        )
        return try await send(endpoint)
    }

    /// Pushes the reading position back to the service so other devices pick it up.
    ///
    /// Both progress values are fractions in `0…1`. The service speaks percentages, so they are
    /// converted on the way out; see `Documentation/API.md`.
    public func updateProgress(
        workId: Int,
        chapterId: Int,
        workProgress: Double,
        chapterProgress: Double,
        sessionId: String? = nil
    ) async throws {
        guard credentials.isAuthenticated else { throw AuthorTodayError.notAuthenticated }

        struct Request: Encodable {
            let workId: Int
            let chapterId: Int
            let workProgress: Double
            let chapterProgress: Double
            let sessionId: String?
        }

        let body = try Self.makeBody(Request(
            workId: workId,
            chapterId: chapterId,
            workProgress: Progress.percentage(workProgress),
            chapterProgress: Progress.percentage(chapterProgress),
            sessionId: sessionId
        ))
        try await sendUnparsed(Endpoint(method: .post, path: "/v1/reader/update-progress", body: body))
    }
}
