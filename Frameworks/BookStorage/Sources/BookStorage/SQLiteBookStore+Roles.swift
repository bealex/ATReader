//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit

/// The narrow views of the store that other modules are given.
///
/// One SQLite file answers all of them, but nothing outside takes the whole forty-method surface: the
/// typesetter asks for bodies and prepared text, the paginator for hashes and placements. What a type
/// declares it needs is what a reader of that type has to understand.
extension SQLiteBookStore: ChapterBodyStore, PreparedChapterStore, PlacementStore, ColumnStore {}
