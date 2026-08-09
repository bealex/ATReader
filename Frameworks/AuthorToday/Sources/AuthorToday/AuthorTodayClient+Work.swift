//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

extension AuthorTodayClient {
    public func workDetails(id: Int, recommendationsCount: Int = 0) async throws -> WorkDetails {
        let endpoint = Endpoint(
            path: "/v1/work/\(id)/details",
            query: [ URLQueryItem(name: "recommendationsCount", value: String(recommendationsCount)) ]
        )
        return try await send(endpoint)
    }

    /// The table of contents. Chapters the reader may not open are still listed, flagged by
    /// ``ChapterInfo/isReadable``.
    public func workContents(id: Int) async throws -> [ChapterInfo] {
        try await send(Endpoint(path: "/v1/work/\(id)/content"))
    }

    /// Fetches a chapter and decrypts it into HTML.
    ///
    /// The key derivation folds in the signed-in account id, so a chapter fetched as a guest and the same
    /// chapter fetched while signed in do not share a key.
    public func chapterText(workId: Int, chapterId: Int) async throws -> ChapterText {
        // Fail here rather than fetching a chapter that cannot be opened: without a certificate the
        // service answers with its own generic error, which tells the developer nothing useful.
        guard configuration.canDecryptChapters else { throw AuthorTodayError.notConfigured }

        let endpoint = Endpoint(path: "/v1/work/\(workId)/chapter/\(chapterId)/text")
        let encrypted: EncryptedChapterText = try await send(endpoint)
        let html = try ChapterDecryptor.decrypt(
            text: encrypted.text,
            key: encrypted.key,
            userId: credentials.userId,
            salt: configuration.chapterSalt,
            certificate: configuration.certificate
        )

        return ChapterText(
            id: encrypted.id,
            title: encrypted.title,
            html: html,
            lastModificationTime: encrypted.lastModificationTime
        )
    }
}
