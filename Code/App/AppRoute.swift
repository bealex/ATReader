//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// Which of the two things the reader is holding together.
enum MergeKind: String, Identifiable {
    case series
    case authors

    var id: String { rawValue }
}

/// The screens any list can push. Each tab owns its own stack of these.
enum AppRoute: Hashable {
    case work(id: Int, title: String)
    case reader(Reader)
    case series(name: String)
    case readerAppearance
    #if DEBUG
        /// The design catalogue, reached from the profile in debug builds.
        case designSystem
    #endif

    struct Reader: Hashable {
        let workId: Int
        let title: String
        /// `nil` asks the reader to resume where the service says the reader stopped.
        let chapterId: Int?
        /// How far into the book the reader stopped, from nought to one, where the opener knows.
        let readingProgress: Double?

        init(workId: Int, title: String, chapterId: Int? = nil, readingProgress: Double? = nil) {
            self.workId = workId
            self.title = title
            self.chapterId = chapterId
            self.readingProgress = readingProgress
        }
    }

    /// How far into the book a route to the reader stops, where it knows.
    var readingProgress: Double? {
        guard case let .reader(reader) = self else { return nil }

        return reader.readingProgress
    }
}
