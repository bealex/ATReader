//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import Foundation

/// Where each book on the device came from, in one place, so any cover can say so.
///
/// A row holds a ``Book``, which is what the book is rather than how it got here. Only the device's own
/// record of an import knows that, and every list would otherwise ask the store the same question a
/// screenful at a time.
@Observable @MainActor
final class BookOrigins {
    private(set) var sources: [Int: BookSource] = [:]

    @ObservationIgnored
    private let store: SQLiteBookStore

    init(store: SQLiteBookStore = .shared) {
        self.store = store
    }

    func refresh() async {
        let held = await store.localBooks()
        let found = held.reduce(into: [Int: BookSource]()) { found, record in found[record.workId] = record.source }

        if sources != found { sources = found }
    }

    /// A book the service numbers is the service's. One numbered below zero is on the device, and its
    /// record says which shelf it came off; a record not read yet leaves it a file, which is what every
    /// book on the device was before a service could bring one in.
    func origin(of workId: Int) -> CoverOrigin {
        guard BookNumbering.isLocal(workId) else { return .service }

        return sources[workId] == .litres ? .litres : .file
    }
}
