//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import CryptoKit
import Foundation
import ImageIO
import OSLog
import UIKit

/// Downloads book covers once, shrinks them to something this screen can actually use, and keeps them
/// on disk.
///
/// The service hands out covers far larger than any row needs, so the expensive part is decoding rather
/// than downloading. Every cover is downsampled through ImageIO on the way in, which never allocates
/// the full-size bitmap, and the result is what gets stored and re-used.
actor CoverCache {
    static let shared = CoverCache()

    private static let log = Logger(subsystem: "com.lonelybytes.atreader", category: "covers")

    /// The longest edge kept on disk, in pixels.
    ///
    /// The widest cover the app draws is the book page's 116pt, so this is that rounded up for a 3x
    /// screen. Smaller rows scale the same image down, which costs nothing and means one file per
    /// cover rather than one per size.
    static let maximumPixelSize = 420

    private let directory: URL
    private let session: URLSession
    private let memory = NSCache<NSString, UIImage>()

    /// In-flight downloads, so a scrolling list asking for the same cover ten times fetches it once.
    private var loading: [URL: Task<UIImage?, Never>] = [:]

    init(directory: URL? = nil, session: URLSession = .shared) {
        let base =
            directory
            ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Covers", isDirectory: true)

        self.directory = base
        self.session = session
        memory.countLimit = 200
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    func image(for url: URL) async -> UIImage? {
        let key = Self.key(for: url)

        if let cached = memory.object(forKey: key as NSString) { return cached }

        if let stored = UIImage(contentsOfFile: fileURL(key).path) {
            memory.setObject(stored, forKey: key as NSString)
            return stored
        }

        if let existing = loading[url] { return await existing.value }

        let task = Task<UIImage?, Never> { [session, directory] in
            await Self.fetch(url, session: session, directory: directory)
        }

        loading[url] = task
        let image = await task.value
        loading[url] = nil

        if let image { memory.setObject(image, forKey: key as NSString) }

        return image
    }

    private static func fetch(_ url: URL, session: URLSession, directory: URL) async -> UIImage? {
        do {
            let (data, _) = try await session.data(from: url)

            guard
                let image = downsample(data, maximumPixelSize: maximumPixelSize)
            else {
                log.error("downsample returned nil")
                return nil
            }
            guard
                let encoded = image.jpegData(compressionQuality: 0.85)
            else {
                log.error("jpegData returned nil")
                return image
            }

            do {
                let destination = directory.appendingPathComponent("\(key(for: url)).jpg")
                try encoded.write(to: destination, options: .atomic)
            } catch {
                log.error("write failed: \(error.localizedDescription, privacy: .public)")
            }

            return image
        } catch {
            log.error("download failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Housekeeping

    func diskUsage() -> Int64 {
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [ .fileSizeKey ]
            )
        else { return 0 }

        return entries.reduce(into: Int64(0)) { total, url in
            total += Int64((try? url.resourceValues(forKeys: [ .fileSizeKey ]).fileSize) ?? 0)
        }
    }

    func clear() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Internals

    private func fileURL(_ key: String) -> URL {
        directory.appendingPathComponent("\(key).jpg")
    }

    /// A stable, filesystem-safe name for a cover URL.
    private static func key(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Decodes straight to the size wanted. `CGImageSourceCreateThumbnailAtIndex` never materialises
    /// the full-resolution bitmap, which is the whole point.
    static func downsample(_ data: Data, maximumPixelSize: Int) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ]

        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        return UIImage(cgImage: thumbnail)
    }
}
