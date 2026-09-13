//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import UIKit

/// Where a cover is drawn, for a zoom to grow a screen out of and shrink it back into.
///
/// A screen with nothing to grow out of cannot be dragged shut either, so this is what lets a book
/// opened from its own page close the way one opened off the shelf does. The view carries a picture of
/// the cover, since a zoom shrinks a screen into whatever its source is showing.
@MainActor
final class CoverAnchor {
    fileprivate(set) weak var view: UIView?

    /// What a zoom is handed, if the cover it belongs to has been drawn.
    var face: UIView? { view }
}

/// The anchor itself, standing behind the cover it is an anchor for.
struct CoverAnchorView: UIViewRepresentable {
    let anchor: CoverAnchor
    let face: UIImage?

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()

        view.contentMode = .scaleToFill
        view.isUserInteractionEnabled = false
        anchor.view = view
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        view.image = face
        anchor.view = view
    }
}
