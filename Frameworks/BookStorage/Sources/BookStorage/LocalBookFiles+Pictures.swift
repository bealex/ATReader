//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Foundation

/// Where a book that came from a file keeps its pictures.
public struct LocalPictureLibrary: PictureLibrary {
    public init() {}

    public func fileURL(forPicture source: String) -> URL? {
        LocalBookFiles.imageURL(source: source)
    }
}
