//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// How a book that came from a file rather than from the service is numbered.
///
/// The service numbers its works from one upwards, so these count down from below zero and the two can
/// never collide. Every table in ``SQLiteBookStore`` is keyed on those numbers, and a screen asks
/// ``isLocal(_:)`` rather than the database whenever the only question is whether to call the service.
public enum LocalBookFiles {
    /// How much room the imported books take on the disk, pictures and covers included.
    public static func diskUsage() -> Int64 { DiskSpace.taken(by: directory) }

    /// Where everything an imported book brought with it is kept: its file, its cover and its pictures.
    public static var directory: URL {
        let base =
            FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Books", isDirectory: true)

        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// What a picker offers when it is asking for a book.
    ///
    /// FB2 has no type of its own on the system, so it is named by its extension, where the system
    /// declares EPUB itself. XML is offered beside them because a file saved from a browser often
    /// arrives typed as that instead, and zip because that is how these books are usually handed out.
    public static var fileTypes: [UTType] {
        [
            UTType(filenameExtension: "fb2"),
            UTType("org.idpf.epub-container") ?? UTType(filenameExtension: "epub"),
            .xml,
            .zip,
        ].compactMap { $0 }
    }

    /// Where a book's own file is kept.
    ///
    /// The picker hands over a URL that stops working the moment its security scope is given up, so the
    /// file itself is copied in. What a book holds is whatever the parser made of it at the time, and a
    /// parser that has since learned something can only be applied to the file.
    public static func fileURL(workId: Int) -> URL {
        directory.appendingPathComponent("\(-workId).fb2z")
    }

    /// Keeps a book's own text, compressed. FB2 is XML around base64, and squeezing it saves about a
    /// third of a file that would otherwise sit on the device at full size for good.
    public static func keep(_ book: Data, workId: Int) throws {
        try ((book as NSData).compressed(using: .zlib) as Data).write(to: fileURL(workId: workId), options: .atomic)
    }

    /// The book's own text as it was imported, where this device still has it.
    public static func keptFile(workId: Int) -> Data? {
        guard
            let squeezed = try? Data(contentsOf: fileURL(workId: workId)),
            let book = try? (squeezed as NSData).decompressed(using: .zlib)
        else { return nil }

        return book as Data
    }

    /// True where the book's own text is still here, which is what lets it be read again without the
    /// reader naming the file. A book imported before it was kept has none.
    public static func hasKeptFile(workId: Int) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(workId: workId).path)
    }

    public static func coverURL(workId: Int) -> URL {
        directory.appendingPathComponent("\(-workId).cover", conformingTo: .jpeg)
    }

    /// A cover at the size a screen can use, whatever size it arrived at.
    ///
    /// The picture a file carries is made for print, and nothing here draws one larger than
    /// ``CoverCache/maximumPixelSize``. What can't be read as a picture is kept as it came.
    public static func held(cover: Data) -> Data {
        held(cover, to: CoverCache.maximumPixelSize, as: .jpeg)
    }

    /// A picture standing in a book, at the size a page draws one.
    ///
    /// Line work is written out as line work. Turning a diagram or a hand-drawn map into a photograph
    /// rings around every stroke, and at these sizes it would save little.
    public static func held(picture: Data) -> Data {
        held(picture, to: BookPicture.maximumPixelSize, as: .asItCame)
    }

    /// How a picture held to a size is written out again.
    private enum Written {
        case jpeg
        case asItCame
    }

    private static func held(_ picture: Data, to edge: Int, as written: Written) -> Data {
        guard
            largestEdge(of: picture) > edge,
            let shrunk = CoverCache.downsample(picture, maximumPixelSize: edge)
        else { return picture }

        let smaller =
            written == .jpeg || isPhotograph(picture)
            ? shrunk.jpegData(compressionQuality: Self.pictureQuality)
            : shrunk.pngData()

        guard let smaller, smaller.count < picture.count else { return picture }

        return smaller
    }

    /// Shrinks every cover and picture kept from before either was held to a size, and says how many it
    /// shrank.
    ///
    /// Reading a picture's size costs no decoding, so a library already holding small ones is one pass
    /// over a few directory listings.
    @discardableResult
    public static func shrinkKeptPictures(in directory: URL? = nil) -> Int {
        let folder = directory ?? Self.directory
        let covers = listing(of: folder).filter { $0.lastPathComponent.hasSuffix(".cover.jpeg") }
        let books = listing(of: folder.appendingPathComponent("Images", isDirectory: true))
        var shrank = 0

        for cover in covers where shrink(cover, to: CoverCache.maximumPixelSize, as: .jpeg) { shrank += 1 }

        for book in books {
            for picture in listing(of: book) where shrink(picture, to: BookPicture.maximumPixelSize, as: .asItCame) {
                shrank += 1
            }
        }

        return shrank
    }

    private static func listing(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    }

    /// Writes a picture out again where it is larger than it is ever drawn. True where it shrank.
    private static func shrink(_ file: URL, to edge: Int, as written: Written) -> Bool {
        guard largestEdge(ofFileAt: file) > edge, let held = try? Data(contentsOf: file) else { return false }

        let smaller = Self.held(held, to: edge, as: written)

        guard smaller.count < held.count else { return false }

        return (try? smaller.write(to: file, options: .atomic)) != nil
    }

    /// True where a picture is a photograph rather than line work, which is how it is written out again.
    private static func isPhotograph(_ picture: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(picture as CFData, nil) else { return false }

        return (CGImageSourceGetType(source) as String?) == "public.jpeg"
    }

    /// How many pixels a picture's longest edge runs to, read from a file's header.
    private static func largestEdge(ofFileAt file: URL) -> Int {
        CGImageSourceCreateWithURL(file as CFURL, nil).map(largestEdge(of:)) ?? 0
    }

    /// How many pixels a picture's longest edge runs to, read from its header rather than by decoding it.
    private static func largestEdge(of picture: Data) -> Int {
        CGImageSourceCreateWithData(picture as CFData, nil).map(largestEdge(of:)) ?? 0
    }

    private static func largestEdge(of source: CGImageSource) -> Int {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return 0 }

        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0

        return max(width, height)
    }

    /// What a photograph is written at. Above this it gains nothing a page or a shelf can show.
    private static let pictureQuality: CGFloat = 0.85

    /// Where a book's pictures are kept, one directory per book so removing the book removes them.
    public static func imagesDirectory(workId: Int) -> URL {
        directory
            .appendingPathComponent("Images", isDirectory: true)
            .appendingPathComponent("\(-workId)", isDirectory: true)
    }

    /// What an `<img src>` in a stored chapter body points at.
    ///
    /// The book is named in the source rather than passed alongside it, so a chapter body carries
    /// everything needed to find its own pictures.
    public static func imageSource(workId: Int, name: String) -> String { "\(-workId)/\(name)" }

    public static func imageURL(source: String) -> URL? {
        let parts = source.split(separator: "/")

        guard parts.count == 2, Int(parts[0]) != nil, !parts[1].contains("..") else { return nil }

        return
            directory
            .appendingPathComponent("Images", isDirectory: true)
            .appendingPathComponent(String(parts[0]), isDirectory: true)
            .appendingPathComponent(String(parts[1]))
    }
}
