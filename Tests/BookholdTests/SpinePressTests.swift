//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Testing
import UIKit

@testable import Bookhold

/// Spines printed away from the main actor, which is where a whole library's worth of them are printed.
///
/// CoreImage, a graphics renderer and a dynamic colour each go somewhere else off the main thread if
/// they are left to find the room's scheme and the screen's density for themselves, and nothing but the
/// pixels catches it.
struct SpinePressTests {
    @Test(arguments: [ true, false ])
    func printsTheSamePictureOffTheMainActorAsOnIt(isDark: Bool) async {
        let artwork = Self.artwork(isDark: isDark)
        let order = Self.order(isDark: isDark)
        let here = await MainActor.run {
            SpinePrint.draw(order, artwork: artwork, density: Self.density, context: SpinePrint.makeContext())
        }
        let there = await Away().pull(order, artwork: artwork, density: Self.density)

        let printed = Self.pixels(of: here.image)

        #expect(printed != nil)
        #expect(here.isDark == there.isDark)
        #expect(printed == Self.pixels(of: there.image))
    }

    @Test
    func readsADarkCoverAsDarkAndALightOneAsLightWhereverItIsPrinted() async {
        let away = Away()
        let dark = await away.pull(Self.order(isDark: false), artwork: Self.artwork(isDark: true), density: 3)
        let light = await away.pull(Self.order(isDark: true), artwork: Self.artwork(isDark: false), density: 3)

        #expect(dark.isDark)
        #expect(!light.isDark)
    }

    @Test
    @MainActor
    func handsBackTheSpineThePressFiledRatherThanPrintingABareOne() {
        let work = Book(
            id: 4242,
            title: "Title",
            authorLine: "Author",
            coverURL: nil,
            annotation: nil,
            textLength: 500_000
        )
        let order = SpinePrint.Order(
            id: work.id,
            number: 1,
            title: "Title",
            size: Self.size,
            isDark: false,
            hasArtwork: true
        )
        let filed = SpinePrint.keep(
            SpinePrint.Impression(image: Self.artwork(isDark: true), isDark: true),
            for: order
        )

        let standing = SpinePrint.standing(of: work, number: 1, title: "Title", size: Self.size, isDark: false)

        #expect(SpinePrint.has(order))
        // The book has no artwork in hand, and the spine printed on it still stands.
        #expect(standing.image === filed)
        #expect(standing.isWanted)
        #expect(SpinePrint.isDark(of: work.id) == true)
    }

    private static let size = CGSize(width: 33, height: 198)
    private static let density: CGFloat = 3

    private static func order(isDark: Bool) -> SpinePrint.Order {
        SpinePrint.Order(id: 1, number: 2, title: "Title", size: size, isDark: isDark, hasArtwork: true)
    }

    /// A cover invented on the spot, so a spine has something to be a blur of.
    private static func artwork(isDark: Bool) -> UIImage {
        let size = CGSize(width: 120, height: 180)

        return UIGraphicsImageRenderer(size: size).image { context in
            (isDark ? UIColor.blue : UIColor.yellow).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            (isDark ? UIColor.purple : UIColor.white).setFill()
            context.fill(CGRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 4))
        }
    }

    private static func pixels(of image: UIImage) -> Data? {
        guard let drawn = image.cgImage else { return nil }

        return drawn.dataProvider?.data as Data?
    }
}

/// A press of the test's own, since the app keeps its one to itself.
private actor Away {
    private let context = SpinePrint.makeContext()

    func pull(_ order: SpinePrint.Order, artwork: UIImage?, density: CGFloat) -> SpinePrint.Impression {
        SpinePrint.draw(order, artwork: artwork, density: density, context: context)
    }
}
