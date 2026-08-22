//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import CryptoKit
import Foundation
import ImageIO
import OSLog
import UIKit

/// Downloads book covers once, shrinks them to something this screen can actually use, and keeps them.
///
/// The service hands out covers far larger than any row needs, so the expensive part is decoding rather
/// than downloading. Every cover is downsampled through ImageIO on the way in, which never allocates the
/// full-size bitmap, and the result is what gets stored, decoded ready for display, and re-used.
///
/// Covers live in Application Support rather than Caches: a shelf that empties itself the first time the
/// device runs low on space is worse than one that holds a bounded number of small files.
actor CoverCache {
    static let shared = CoverCache()

    private static let logger = Logger(subsystem: "com.lonelybytes.atreader", category: "covers")

    /// The longest edge kept on disk, in pixels.
    ///
    /// The widest cover the app draws is the reader's title page at 150pt, so this is that rounded up
    /// for a 3x screen. Smaller rows scale the same image down, which costs nothing and means one file
    /// per cover rather than one per size.
    static let maximumPixelSize = 480

    /// How many covers to keep. Roughly 30 KB each, so the whole shelf is tens of megabytes.
    static let maximumCoverCount = 2000

    private let directory: URL
    private let session: URLSession
    private let memory = NSCache<NSString, UIImage>()

    /// In-flight downloads, so a scrolling list asking for the same cover ten times fetches it once.
    private var loading: [URL: Task<UIImage?, Never>] = [:]

    /// Writes since the last sweep, so eviction runs now and then rather than on every cover.
    private var writesSinceSweep = 0
    private var hasSwept = false

    init(directory: URL? = nil, session: URLSession = .shared) {
        let base =
            directory
            ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Covers", isDirectory: true)

        self.directory = base
        self.session = session
        memory.countLimit = 300
        // Four bytes a pixel, so a 480pt-tall cover costs about 1 MB decoded.
        memory.totalCostLimit = 96 * 1024 * 1024
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        Self.excludeFromBackup(base)
    }

    func image(for url: URL) async -> UIImage? {
        let key = Self.fileKey(for: url)

        if let cached = memory.object(forKey: key as NSString) { return cached }

        if let stored = await Self.decode(fileURL(key)) {
            remember(stored, key: key)
            touch(fileURL(key))
            return stored
        }

        if let existing = loading[url] { return await existing.value }

        let task = Task<UIImage?, Never> { [session, directory] in
            await Self.fetch(url, session: session, directory: directory)
        }

        loading[url] = task
        let image = await task.value
        loading[url] = nil

        if let image {
            remember(image, key: key)
            writesSinceSweep += 1
        }

        await sweepIfDue()
        return image
    }

    /// Warms the covers a list is about to show. Failures are silent — this is only ever an optimisation.
    func prefetch(_ urls: [URL]) async {
        for url in urls where memory.object(forKey: Self.fileKey(for: url) as NSString) == nil {
            _ = await image(for: url)
        }
    }

    private func remember(_ image: UIImage, key: String) {
        let cost = Int(image.size.width * image.scale * image.size.height * image.scale) * 4
        memory.setObject(image, forKey: key as NSString, cost: cost)
    }

    private static func fetch(_ url: URL, session: URLSession, directory: URL) async -> UIImage? {
        do {
            let (data, _) = try await session.data(from: url)

            guard
                let image = downsample(data, maximumPixelSize: maximumPixelSize)
            else {
                logger.error("downsample returned nil")
                return nil
            }
            guard
                let encoded = image.jpegData(compressionQuality: 0.85)
            else {
                logger.error("jpegData returned nil")
                return image
            }

            do {
                let destination = directory.appendingPathComponent("\(fileKey(for: url)).jpg")
                try encoded.write(to: destination, options: .atomic)
            } catch {
                logger.error("write failed: \(error.localizedDescription, privacy: .public)")
            }

            return image.preparingForDisplay() ?? image
        } catch {
            logger.error("download failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Reads and decodes a stored cover away from the main actor, ready to draw without decoding again.
    private static func decode(_ url: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(contentsOfFile: url.path) else { return nil }

            return image.preparingForDisplay() ?? image
        }.value
    }

    // MARK: - Housekeeping

    /// Drops the oldest covers once the shelf outgrows ``maximumCoverCount``.
    private func sweepIfDue() async {
        guard !hasSwept || writesSinceSweep >= 50 else { return }

        hasSwept = true
        writesSinceSweep = 0
        let directory = directory

        await Task.detached(priority: .background) {
            let keys: [URLResourceKey] = [ .contentModificationDateKey ]

            guard
                let entries = try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: keys
                ),
                entries.count > CoverCache.maximumCoverCount
            else { return }

            let byAge = entries.sorted { left, right in
                let leftDate =
                    (try? left.resourceValues(forKeys: [ .contentModificationDateKey ]))?
                    .contentModificationDate ?? .distantPast
                let rightDate =
                    (try? right.resourceValues(forKeys: [ .contentModificationDateKey ]))?
                    .contentModificationDate ?? .distantPast
                return leftDate < rightDate
            }

            for url in byAge.prefix(entries.count - CoverCache.maximumCoverCount) {
                try? FileManager.default.removeItem(at: url)
            }
        }.value
    }

    /// Marks a cover as used, so eviction takes the ones nobody looks at. Skipped when it was already
    /// touched today: this runs while a list scrolls.
    private func touch(_ url: URL) {
        let modified = (try? url.resourceValues(forKeys: [ .contentModificationDateKey ]))?.contentModificationDate

        guard modified == nil || modified! < Date.now.addingTimeInterval(-24 * 60 * 60) else { return }

        try? FileManager.default.setAttributes([ .modificationDate: Date.now ], ofItemAtPath: url.path)
    }

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
        Self.excludeFromBackup(directory)
    }

    // MARK: - Internals

    private func fileURL(_ key: String) -> URL {
        directory.appendingPathComponent("\(key).jpg")
    }

    /// A stable, filesystem-safe name for a cover URL.
    private static func fileKey(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
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

/// The covers already decoded this run, reachable without an `await`.
///
/// ``CoverCache`` is an actor, so a view rebuilt under a new identity draws its placeholder until the
/// hop returns. A cover already in hand appears in the first frame instead.
@MainActor
enum CoverImages {
    private static let images: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 300
        return cache
    }()

    static func image(for url: URL) -> UIImage? { images.object(forKey: url as NSURL) }

    static func remember(_ image: UIImage, for url: URL) { images.setObject(image, forKey: url as NSURL) }
}
