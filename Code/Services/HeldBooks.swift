//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import Foundation

/// What the library already holds, by name, so a catalogue can mark a book the reader has.
///
/// A catalogue offers a title and an author line and nothing else two copies of one book would share,
/// so the mark is a guess; the file itself decides, and a download of a book already here lands on the
/// row it is already on.
@Observable @MainActor
final class HeldBooks {
    /// The author words of every held book, under its title, since one title can stand for several.
    private(set) var byTitle: [String: [Set<String>]] = [:]

    @ObservationIgnored
    private let store: SQLiteBookStore

    init(store: SQLiteBookStore = .shared) {
        self.store = store
    }

    func refresh() async {
        note(await store.books())
    }

    /// Takes the library as it stands, for a caller that has read it already.
    func note(_ books: [Book]) {
        let found = books.reduce(into: [String: [Set<String>]]()) { found, book in
            found[Self.key(of: book.title), default: []].append(Self.words(of: book.authorLine))
        }

        if byTitle != found { byTitle = found }
    }

    /// Whether a book of this name is on the shelf already.
    ///
    /// The title has to match outright and the author only has to agree, because a catalogue spells a
    /// name every way there is and plenty of them give no author at all.
    func holds(title: String, authors: [String]) -> Bool {
        guard let held = byTitle[Self.key(of: title)] else { return false }

        let wanted = Self.words(of: authors.joined(separator: " "))

        return held.contains { $0.isEmpty || wanted.isEmpty || !$0.isDisjoint(with: wanted) }
    }

    /// A name stripped to what two spellings of it share: case, accents and punctuation all go.
    private static func key(of text: String) -> String {
        text
            .folding(options: [ .caseInsensitive, .diacriticInsensitive, .widthInsensitive ], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The words of a name worth matching on. An initial is left out, since it agrees with everything.
    private static func words(of line: String) -> Set<String> {
        Set(key(of: line).split(separator: " ").filter { $0.count > 2 }.map(String.init))
    }
}
