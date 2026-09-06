//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookRenderer
import BookStorage
import Foundation

/// Where the typesetter is handed the store and the picture shelf it works over.
///
/// BookRenderer names neither: it asks for the two narrow things it needs and the app decides that
/// both are the one SQLite file and the folder an imported book unpacked into.
extension BookProcessor {
    static let shared = BookProcessor(store: SQLiteBookStore.shared)
}

extension BookPagination {
    /// The paginator over this app's store.
    static func make(workId: Int, context: ChapterLayout.Context) -> BookPagination {
        make(workId: workId, context: context, store: SQLiteBookStore.shared)
    }
}

/// The page's covers, from the shelf the app keeps them on.
///
/// Downsampled once and kept on disk by CoverCache, then held to the page's own two colours by the
/// typesetter. The page asks for a picture and learns neither of those things.
struct CoverPictures: PagePictureLoading {
    @MainActor
    func picture(at url: URL) async -> PageImage? {
        guard let loaded = await CoverCache.shared.image(for: url) else { return nil }

        return BookImages.shared.prepare(loaded, key: "cover:\(url.absoluteString)")
    }
}

enum Renderers {
    /// Told once at launch where a book from a file keeps its pictures.
    @MainActor
    static func connect() {
        BookImages.pictures = LocalPictureLibrary()
    }
}
