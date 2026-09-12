//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookStorage
import Foundation
import OSLog
import UIKit

/// The library, kept in a folder the reader picked, and put back from it.
///
/// A folder rather than the device's own backup, which the store deliberately stays out of. Books
/// imported from a file are the reason: nothing else on the device holds them, so nothing else can
/// give them back. The folder is remembered as a bookmark, since a URL a picker hands over stops
/// working the moment its scope is given up.
@Observable @MainActor
final class LibraryBackup {
    enum Stage: Equatable {
        case idle
        case working
        case done(String)
        case failed(String)
    }

    private(set) var stage: Stage = .idle
    /// Where the chosen folder is, as the Files app would name it, for a reader who wants to know where
    /// their books went: "iCloud Drive/Books/Backup".
    private(set) var folderPath: String?
    /// When the folder was last written to, as the backup itself says.
    private(set) var writtenAt: Date?
    /// How much the backup in the folder holds.
    private(set) var bytes: Int64?

    var isWorking: Bool { stage == .working }
    var hasFolder: Bool { folderPath != nil }

    @ObservationIgnored
    private let logger = Logger(subsystem: "com.lonelybytes.atreader", category: "backup")

    private static let key = "backup.folder"

    init() {
        refresh()
    }

    /// Remembers a folder the reader picked.
    func choose(_ folder: URL) {
        do {
            let scoped = folder.startAccessingSecurityScopedResource()

            defer {
                if scoped { folder.stopAccessingSecurityScopedResource() }
            }

            UserDefaults.standard.set(try folder.bookmarkData(), forKey: Self.key)
            stage = .idle
            refresh()
        } catch {
            stage = .failed(String(localized: "That folder could not be remembered."))
            logger.error("bookmarking failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Whether this is the folder already chosen.
    func isCurrent(_ folder: URL) -> Bool {
        resolved()?.standardizedFileURL == folder.standardizedFileURL
    }

    func forget() {
        UserDefaults.standard.removeObject(forKey: Self.key)
        folderPath = nil
        writtenAt = nil
        bytes = nil
        stage = .idle
    }

    /// Writes everything the device holds into the folder.
    func backUp() async {
        // The folder's row says how much it holds and when it was written, so a backup that worked
        // leaves nothing else to say.
        await working { folder in
            _ = try await LibraryArchive.write(to: folder, store: .shared)

            return nil
        }
    }

    /// Puts the folder's copy back, in place of everything the device holds now.
    func restore() async {
        await working { folder in
            // A folder in iCloud may hold nothing but placeholders until somebody asks for the files.
            try? FileManager.default.startDownloadingUbiquitousItem(at: LibraryArchive.home(in: folder))

            let manifest = try await LibraryArchive.read(from: folder, store: .shared)

            let written = manifest.writtenAt.formatted(date: .abbreviated, time: .shortened)

            return String(localized: "Restored the backup from \(written)")
        }
    }

    /// Holds the folder open for as long as the work takes, and says what came of it.
    private func working(_ work: (URL) async throws -> String?) async {
        guard
            let folder = resolved()
        else {
            stage = .failed(String(localized: "That folder is no longer reachable. Choose it again."))
            return
        }

        let scoped = folder.startAccessingSecurityScopedResource()

        defer {
            if scoped { folder.stopAccessingSecurityScopedResource() }
        }

        stage = .working

        do {
            stage = try await work(folder).map(Stage.done) ?? .idle
            refresh()
        } catch {
            stage = .failed(String(describing: error))
            logger.error("backup failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The folder the bookmark stands for, where it still stands for one.
    private func resolved() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Self.key) else { return nil }

        var stale = false
        let folder = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)

        // A stale bookmark still opens; it is the next launch that would find nothing, so it is
        // written down again while there is something to write.
        if stale, let folder, let fresh = try? folder.bookmarkData() {
            UserDefaults.standard.set(fresh, forKey: Self.key)
        }

        return folder
    }

    /// The folder's path from the root the Files app shows it under, or the whole path where that root
    /// can't be told from the URL.
    private static func readablePath(of folder: URL) -> String {
        let parts = folder.standardizedFileURL.pathComponents
        let roots = [
            ("com~apple~CloudDocs", "iCloud Drive"),
            ("File Provider Storage", String(localized: "On My \(UIDevice.current.model)")),
        ]

        for (marker, root) in roots {
            guard let index = parts.lastIndex(of: marker) else { continue }

            return ([ root ] + parts[(index + 1)...]).joined(separator: "/")
        }

        return folder.path
    }

    private func refresh() {
        guard let folder = resolved() else { return folderPath = nil }

        folderPath = Self.readablePath(of: folder)

        let scoped = folder.startAccessingSecurityScopedResource()

        defer {
            if scoped { folder.stopAccessingSecurityScopedResource() }
        }

        let manifest = LibraryArchive.manifest(in: folder)

        writtenAt = manifest?.writtenAt
        bytes = manifest?.bytes
    }
}
