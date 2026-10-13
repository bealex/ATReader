//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// The book the reader has open, kept so the next launch opens on it again.
///
/// Written as a book opens and taken back as it shuts, so an app put away or killed mid-book has
/// nothing left to write. Where in the book is the reading position's business.
@MainActor
enum OpenBook {
    struct Kept: Equatable {
        let workId: Int
        let title: String
    }

    private static let workIdKey = "openBook.workId"
    private static let titleKey = "openBook.title"
    private static var hasBeenTaken = false

    static func keep(_ book: Kept, in defaults: UserDefaults = .standard) {
        defaults.set(book.workId, forKey: workIdKey)
        defaults.set(book.title, forKey: titleKey)
    }

    /// Forgets the book once it has shut, unless another window has opened a different one since.
    static func forget(workId: Int, in defaults: UserDefaults = .standard) {
        guard kept(in: defaults)?.workId == workId else { return }

        defaults.removeObject(forKey: workIdKey)
        defaults.removeObject(forKey: titleKey)
        PagePicture.forget(in: defaults)
    }

    static func kept(in defaults: UserDefaults = .standard) -> Kept? {
        // A book from a file is numbered below zero, so nought is the one number that is no book.
        let workId = defaults.integer(forKey: workIdKey)

        guard workId != 0, let title = defaults.string(forKey: titleKey) else { return nil }

        return Kept(workId: workId, title: title)
    }

    /// The book to open this launch on, answered once: every window asks, and one book opens in one.
    static func takeForLaunch() -> Kept? {
        guard !hasBeenTaken else { return nil }

        hasBeenTaken = true

        return forLaunch
    }

    /// The book a launch opens on, whether or not a window has taken it yet.
    static var forLaunch: Kept? {
        #if DEBUG
            // A launch driven by a test or a debug switch starts where that switch says, unless it
            // asks for this with `-at-restores-book YES`.
            let isDriven = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-at-") }

            if isDriven, !UserDefaults.standard.bool(forKey: "at-restores-book") { return nil }
        #endif

        return kept()
    }
}
