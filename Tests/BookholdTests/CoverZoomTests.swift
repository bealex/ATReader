//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Testing
import UIKit

@testable import Bookhold

/// A book opened from its own page grows out of the cover at the top of it.
///
/// The rule is the shelf's: while the zoom runs the anchor stands in for the cover, so the screen
/// growing out of it and the cover it grew out of are never both drawn. Two of one cover, one growing
/// and one holding still, is what gives the zoom away.
@MainActor
struct CoverZoomTests {
    @Test
    func showsNothingOfItsOwnUntilNoZoomIsRunning() {
        let anchor = CoverAnchor()

        #expect(!anchor.isZooming, "a cover nothing is zooming into draws itself")

        _ = anchor.face(during: .running)

        #expect(anchor.isZooming)

        _ = anchor.face(during: .covered)

        #expect(anchor.isZooming)

        _ = anchor.face(during: .done)

        #expect(!anchor.isZooming, "the cover never came back")
    }

    /// The anchor carries the whole cover, and goes itself once the reader covers the screen.
    @Test
    func standsInForTheCoverWhileTheZoomRuns() {
        let anchor = CoverAnchor()
        let view = UIImageView()

        anchor.stands(on: view)
        anchor.picture = UIImage()

        #expect(anchor.face(during: .running) === view)
        #expect(view.image === anchor.picture, "the zoom grew out of a bare view")
        #expect(!view.isHidden)

        _ = anchor.face(during: .covered)

        #expect(view.isHidden, "the anchor stayed on a screen the reader had covered")

        _ = anchor.face(during: .done)

        #expect(!view.isHidden)
    }
}

/// The order a book on the shelf goes through while it is opened and closed again.
///
/// Written down because it has broken more than once, and every way it broke looked like something
/// else: a cover drawn beside its own stand-in reads as the zoom having gone wrong, and a book left
/// standing aside reads as the shelf having lost it.
@MainActor
struct BookZoomSequenceTests {
    /// The stand-in and the cover are never both drawn, and never both away except while the reader is
    /// over the shelf.
    @Test
    func standsInForTheCoverFromTheFirstFrameToTheLast() {
        let book = BookView()

        #expect(book.showsItsOwnCover, "a book nothing is zooming stands on its own panels")

        // Out of the shelf: the stand-in takes the cover's place, at the cover's own place.
        _ = book.face(during: .running)

        #expect(book.showsTheStandIn)
        #expect(!book.showsItsOwnCover, "the cover was drawn beside its own stand-in")

        // The reader is over the shelf, so neither is worth drawing.
        _ = book.face(during: .covered)

        #expect(!book.showsTheStandIn)
        #expect(!book.showsItsOwnCover)

        // Back out: the stand-in is what the screen shrinks into, so it is there again and the cover
        // is not.
        _ = book.face(during: .running)

        #expect(book.showsTheStandIn)
        #expect(!book.showsItsOwnCover, "the cover came back before the zoom had finished")

        // Settled in the cover's place: the two swap, and no frame has neither on it.
        _ = book.face(during: .done)

        #expect(book.showsItsOwnCover, "the cover never came back")
        #expect(!book.showsTheStandIn, "the stand-in stayed on the shelf beside the cover")
    }

    /// A view laid with the spares carries no zoom into the next book to take it.
    ///
    /// The shelf keeps a pile of views to hand out, and one that went onto it mid-zoom would otherwise
    /// refuse to stand up for the book that took it next, leaving an empty board where a book is.
    @Test
    func aBookBackFromTheSparesStandsAsItself() {
        let book = BookView()

        _ = book.face(during: .covered)

        #expect(!book.showsItsOwnCover)

        book.retire()
        book.standAsTheZoomAsks()

        #expect(book.showsItsOwnCover, "a book back from the spares stood aside for a zoom that ended elsewhere")
    }

    /// A book the shelf lays out again while its zoom is still running is left standing aside.
    ///
    /// The shelf dresses every book on every pass, and opening one guarantees a pass: the position
    /// written when the chapter lands re-orders the shelves. Dressing that put the panels back up left
    /// the cover on the shelf behind the pages it had just grown into, and the book knew it was
    /// standing aside the whole time.
    @Test
    func dressingABookLeavesItStandingAside() {
        for stage in [ BookZoom.running, .covered ] {
            let book = BookView()

            _ = book.face(during: stage)
            book.show(Self.somethingToStand)

            #expect(!book.showsItsOwnCover, "dressing stood the book up in the middle of a \(stage) zoom")
            #expect(book.showsTheStandIn == (stage == .running))
        }
    }

    /// A book nothing is zooming is dressed onto its own panels, as every book on the shelf is.
    @Test
    func dressingABookNothingIsZoomingStandsItUp() {
        let book = BookView()

        _ = book.face(during: .done)
        book.show(Self.somethingToStand)

        #expect(book.showsItsOwnCover)
        #expect(!book.showsTheStandIn)
    }

    /// A volume the reader doesn't hold, which stands without a book to build one from.
    private static let somethingToStand = BookView.Contents(
        stands: .gap(3),
        edge: 12,
        face: 40,
        standing: 60,
        box: 70
    )
}
