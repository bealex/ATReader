//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// What can go wrong reading a book out of a file, whatever format the file is in.
public enum BookFileError: LocalizedError {
    case unreadable
    case malformed(String?)
    case notABook
    case emptyArchive
    case protectedArchive
    /// The book is sealed by whoever sold it, and there is no key for it here.
    case protectedBook
    /// The book is set page by page and cannot be reflowed to this screen.
    case fixedLayout

    public var errorDescription: String? {
        switch self {
            case .unreadable: String(localized: "That file couldn’t be read.")
            case let .malformed(detail):
                detail.map { String(localized: "That file is damaged: \($0)") }
                    ?? String(localized: "That file is damaged.")
            case .notABook: String(localized: "That file has no text in it.")
            case .emptyArchive: String(localized: "That archive has no book in it.")
            case .protectedArchive: String(localized: "That archive is password-protected.")
            case .protectedBook: String(localized: "That book has DRM on it and can’t be opened here.")
            case .fixedLayout:
                String(localized: "That book is laid out page by page, and this reader can only reflow text.")
        }
    }
}
