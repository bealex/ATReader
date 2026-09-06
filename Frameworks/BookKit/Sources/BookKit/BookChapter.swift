//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// One entry of a book's table of contents.
public struct BookChapter: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let workId: Int?
    public let title: String?
    public let isDraft: Bool?
    public let sortOrder: Int?
    public let publishTime: Date?
    public let lastModificationTime: Date?
    public let textLength: Int?
    public let isAvailable: Bool?

    public init(
        id: Int,
        workId: Int?,
        title: String?,
        isDraft: Bool? = nil,
        sortOrder: Int?,
        publishTime: Date? = nil,
        lastModificationTime: Date? = nil,
        textLength: Int?,
        isAvailable: Bool? = nil
    ) {
        self.id = id
        self.workId = workId
        self.title = title
        self.isDraft = isDraft
        self.sortOrder = sortOrder
        self.publishTime = publishTime
        self.lastModificationTime = lastModificationTime
        self.textLength = textLength
        self.isAvailable = isAvailable
    }

    /// A draft is listed in the contents but carries no body anyone can read.
    public var isReadable: Bool { isAvailable != false && isDraft != true }
}
