//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

public enum FB2Error: LocalizedError {
    case unreadable
    case malformed(String?)
    case notABook
    case emptyArchive
    case protectedArchive

    public var errorDescription: String? {
        switch self {
            case .unreadable: String(localized: "That file couldn’t be read.")
            case let .malformed(detail):
                detail.map { String(localized: "That file isn’t valid FB2: \($0)") }
                    ?? String(localized: "That file isn’t valid FB2.")
            case .notABook: String(localized: "That FB2 file has no text in it.")
            case .emptyArchive: String(localized: "That archive has no book in it.")
            case .protectedArchive: String(localized: "That archive is password-protected.")
        }
    }
}
