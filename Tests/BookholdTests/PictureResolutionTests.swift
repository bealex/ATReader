//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import Foundation
import Testing
import UIKit

@testable import Bookhold

/// Covers and the pictures inside a book are kept at the size a screen draws them, whatever size they
/// arrived at.
struct PictureResolutionTests {
    /// A cover the size a file carries one, drawn rather than taken from a book.
    private func cover(width: Int, height: Int) -> Data {
        let size = CGSize(width: width, height: height)
        // One pixel to the point, so the picture is the size it is asked for rather than the screen's.
        let format = UIGraphicsImageRendererFormat.default()

        format.scale = 1

        let drawn = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height / 3))
        }

        return drawn.jpegData(compressionQuality: 0.9) ?? Data()
    }

    private func size(of picture: Data) -> CGSize {
        UIImage(data: picture).map { CGSize(width: $0.size.width * $0.scale, height: $0.size.height * $0.scale) }
            ?? .zero
    }

    @Test
    func aPrintSizedCoverIsKeptAtTheSizeAScreenDrawsIt() {
        let held = LocalBookFiles.held(cover: cover(width: 1500, height: 2359))
        let size = size(of: held)

        #expect(Int(max(size.width, size.height)) <= CoverCache.maximumPixelSize)
        #expect(abs(size.height / size.width - 2359.0 / 1500.0) < 0.02, "the cover changed shape")
    }

    /// One already small enough is kept exactly as it came, rather than written out again.
    @Test
    func aCoverAlreadySmallEnoughIsLeftAlone() {
        let small = cover(width: 300, height: 450)

        #expect(LocalBookFiles.held(cover: small) == small)
    }

    /// A picture standing in a book is held to what a page draws, which is wider than a cover.
    @Test
    func aPictureIsKeptAtTheSizeAPageDrawsIt() {
        let held = LocalBookFiles.held(picture: cover(width: 2400, height: 1800))
        let size = size(of: held)

        #expect(Int(max(size.width, size.height)) <= BookPicture.maximumPixelSize)
        #expect(Int(max(size.width, size.height)) > CoverCache.maximumPixelSize, "a page holds more than a shelf")
    }

    /// Line work stays line work: a drawing written out as a photograph rings around every stroke.
    @Test
    func lineWorkIsWrittenOutAsLineWork() throws {
        let size = CGSize(width: 2000, height: 1200)
        let format = UIGraphicsImageRendererFormat.default()

        format.scale = 1

        let drawing = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setStroke()
            context.cgContext.setLineWidth(6)
            context.cgContext.stroke(CGRect(x: 100, y: 100, width: 1800, height: 1000))
        }
        let written = LocalBookFiles.held(picture: try #require(drawing.pngData()))

        #expect(written.starts(with: [ 0x89, 0x50, 0x4E, 0x47 ]), "the drawing came back as something else")
    }

    /// The pass over pictures kept before they were held to a size.
    @Test
    func theKeptCoversAreShrunkOnce() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("covers-\(UUID().uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let big = folder.appendingPathComponent("-1000000.cover.jpeg")
        let small = folder.appendingPathComponent("-2000000.cover.jpeg")
        let inside = folder.appendingPathComponent("Images/1000000", isDirectory: true)
        let picture = inside.appendingPathComponent("plate.jpeg")
        let kept = cover(width: 300, height: 450)

        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        try cover(width: 1500, height: 2359).write(to: big)
        try kept.write(to: small)
        try cover(width: 2400, height: 1800).write(to: picture)

        #expect(LocalBookFiles.shrinkKeptPictures(in: folder) == 2)
        #expect(Int(size(of: try Data(contentsOf: big)).height) <= CoverCache.maximumPixelSize)
        #expect(Int(size(of: try Data(contentsOf: picture)).width) <= BookPicture.maximumPixelSize)
        #expect(try Data(contentsOf: small) == kept, "a cover already small enough was written again")
        #expect(LocalBookFiles.shrinkKeptPictures(in: folder) == 0, "the pass shrank something twice")
    }
}
