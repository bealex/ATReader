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

        init(workId: Int, title: String, chapterId: Int? = nil) {
            self.workId = workId
            self.title = title
            self.chapterId = chapterId
        }
    }
}
