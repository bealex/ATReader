//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import Testing
import UIKit

@testable import Bookhold

/// Which launches the picture of a page left open may stand in for the page on.
@MainActor
struct PagePictureTests {
    private static let subject = PagePicture.Subject(workId: -7, theme: "paper", size: CGSize(width: 40, height: 60))

    @Test
    func standsInForTheSameBookInTheSameTheme() async throws {
        let desk = try Self.desk()

        await PagePicture.keep(Self.picture(), of: Self.subject, in: desk.defaults, directory: desk.directory)

        let kept = try #require(PagePicture.kept(workId: -7, theme: "paper", in: desk.defaults, directory: desk.directory))

        #expect(kept.size == Self.subject.size)
        #expect(PagePicture.subject(in: desk.defaults) == Self.subject)
    }

    /// A page drawn light is not shown under a launch that has turned dark, nor the other way round.
    @Test
    func standsAsideWhenTheThemeHasTurned() async throws {
        let desk = try Self.desk()

        await PagePicture.keep(Self.picture(), of: Self.subject, in: desk.defaults, directory: desk.directory)

        #expect(PagePicture.kept(workId: -7, theme: "night", in: desk.defaults, directory: desk.directory) == nil)
    }

    @Test
    func standsAsideForAnotherBook() async throws {
        let desk = try Self.desk()

        await PagePicture.keep(Self.picture(), of: Self.subject, in: desk.defaults, directory: desk.directory)

        #expect(PagePicture.kept(workId: -8, theme: "paper", in: desk.defaults, directory: desk.directory) == nil)
    }

    @Test
    func goesWithTheBookWhenItShuts() async throws {
        let desk = try Self.desk()

        OpenBook.keep(.init(workId: -7, title: "Проба"), in: desk.defaults)
        await PagePicture.keep(Self.picture(), of: Self.subject, in: desk.defaults, directory: desk.directory)
        PagePicture.forget(in: desk.defaults, directory: desk.directory)

        #expect(PagePicture.subject(in: desk.defaults) == nil)
        #expect(PagePicture.kept(workId: -7, theme: "paper", in: desk.defaults, directory: desk.directory) == nil)
    }

    private static func picture() -> UIImage {
        let format = UIGraphicsImageRendererFormat()

        // More pixels than points, as a phone's screen has: the picture has to come back the size
        // of the window it was taken in.
        format.scale = 3

        return UIGraphicsImageRenderer(size: subject.size, format: format).image { drawn in
            UIColor.white.setFill()
            drawn.fill(CGRect(origin: .zero, size: subject.size))
        }
    }

    /// Defaults and a directory of this test's own.
    private static func desk() throws -> (defaults: UserDefaults, directory: URL) {
        let name = "page-picture-\(UUID())"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return (try #require(UserDefaults(suiteName: name)), directory)
    }
}
