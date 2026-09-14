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
///
/// The cover itself stands aside while the zoom runs and the anchor stands in for it, which is what the
/// shelf does with a book's panels: two of one cover, one growing and one holding still, is the thing
/// a zoom out of a cover must never show.
@Observable @MainActor
final class CoverAnchor {
    @ObservationIgnored
    private weak var view: UIImageView?

    /// The cover as it is drawn, its marks included, kept against the moment a zoom asks for it.
    @ObservationIgnored
    var picture: UIImage?

    /// Where a zoom into this cover has got to, and nothing at all while none is running.
    private(set) var zoom: BookZoom?

    /// True while the cover is to leave the drawing to the anchor.
    var isZooming: Bool { zoom == .running || zoom == .covered }

    /// Where the cover is drawn, told by the view that draws it.
    func stands(on view: UIImageView) { self.view = view }

    /// What a zoom is handed, and what stands in the cover's place at each point of it.
    ///
    /// Once the reader covers the screen the anchor goes too, so the last frame of the zoom has neither
    /// it nor the cover on it rather than both.
    func face(during zoom: BookZoom) -> UIView? {
        self.zoom = zoom
        view?.image = picture
        view?.isHidden = zoom == .covered

        return view
    }
}

/// The anchor itself, standing where the cover is drawn.
struct CoverAnchorView: UIViewRepresentable {
    let anchor: CoverAnchor

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()

        view.contentMode = .scaleToFill
        view.isUserInteractionEnabled = false
        anchor.stands(on: view)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        anchor.stands(on: view)
    }
}
