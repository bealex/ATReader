//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// The book a fresh install opens with, read onto the shelf once.
///
/// Once and once only. A reader who deletes it has deleted it, and a book that came back on the next
/// launch would be one they couldn't be rid of. The mark goes down even where the reading-in failed,
/// since a file this build can't read won't read any better tomorrow.
@MainActor
enum FirstBook {
    /// The file is bundled under a name of its own rather than the book's: what the book is called
    /// comes out of the file, so swapping the file swaps the book.
    private static let file = "first-book.fb2"

    private static let mark = "firstBook.offered"

    static func offer(through inbox: BookInbox) async {
        let defaults = UserDefaults.standard

        guard !defaults.bool(forKey: mark) else { return }
        guard let book = Bundle.main.url(forResource: file, withExtension: "zip") else { return }

        await inbox.accept(book)
        defaults.set(true, forKey: mark)
    }
}
