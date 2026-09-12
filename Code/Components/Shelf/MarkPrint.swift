//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import DesignSystem
import SwiftUI
import UIKit

/// What the bookmarks on a shelf's covers carry, printed once each and kept.
///
/// The ribbon itself is drawn by the cover, which knows how wide it is; only the figure or the glyph on
/// it is a picture. A figure is a whole percentage, so a library shares a hundred of them.
@MainActor
enum MarkPrint {
    private static let prints = NSCache<NSString, UIImage>()

    /// What a bookmark carries, set by the same view the app's lists use.
    static func face(_ face: BookmarkMark.Face) -> UIImage {
        let key = "face|\(face)" as NSString

        if let held = prints.object(forKey: key) { return held }

        let renderer = ImageRenderer(content: BookmarkFace(face))

        renderer.scale = SpinePrint.density

        let image = renderer.uiImage ?? UIImage()

        prints.setObject(image, forKey: key)

        return image
    }
}
