//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import Foundation
import Litres
import OSLog

/// Brings the reader's Litres books onto the device, once.
///
/// Not a service the app lives beside, the way it lives beside author.today: a reader signs in, their
/// books come across, and there is nothing left to watch. So this walks the whole library in one go,
/// fetches what is missing or behind, and stops.
@Observable @MainActor
final class LitresSync {
    /// One book that did not come across, and why.
    ///
    /// Kept one by one rather than counted, because a count says a synchronisation went wrong and
    /// nothing about what to do next: the same number can mean the session ran out halfway, or that a
    /// few books have no FB2 at all.
    struct Failure: Sendable, Equatable, Identifiable {
        let id: Int
        let title: String
        let reason: String
    }

    /// What a run came to.
    struct Report: Sendable, Equatable {
        var added = 0
        var updated = 0
        /// Already here and current, or already here from somewhere else.
        var alreadyHere = 0
        /// In the library, and the service offers no FB2 for it: an audiobook, a workbook.
        var notBooks = 0
        var failed = 0

        var total: Int { added + updated + alreadyHere + failed }
    }

    enum Stage: Equatable {
        case idle
        /// Walking the library, which happens before anything can be counted.
        case reading
        case working(done: Int, total: Int, title: String)
        case done(Report)
        case failed(String)
    }

    private(set) var stage: Stage = .idle
    /// Every book that did not come across, in the order they were tried.
    private(set) var failures: [Failure] = []
    /// What was not a book at all, kept for the same reason.
    private(set) var skipped: [Failure] = []

    /// How many books this run actually wrote to the device, counted as they land.
    @ObservationIgnored
    private var broughtAcross = 0

    var isRunning: Bool {
        switch stage {
            case .reading, .working: true
            case .idle, .done, .failed: false
        }
    }

    @ObservationIgnored
    private let logger = Logger(subsystem: "com.lonelybytes.atreader", category: "litres")

    @ObservationIgnored
    private lazy var client = LitresClient(configuration: .init(userAgent: LitresStore.userAgent))

    @ObservationIgnored
    private let store: SQLiteBookStore

    init(store: SQLiteBookStore = .shared) {
        self.store = store
    }

    /// Walks the library and brings across everything the device does not already have.
    func bringEverything(as session: LitresSession) async {
        stage = .reading

        failures = []
        skipped = []
        broughtAcross = 0

        // A library can name the same work twice. Fetching it twice would be two downloads for one
        // book, and the second would only find the first already here.
        var handled: Set<Int> = []

        do {
            // Everything in the library is asked about, whatever the service files it under. What
            // decides is the list of files it offers: a work with an FB2 comes across, and a work
            // without one is reported as such rather than passed over on the strength of a number.
            let books = try await client.wholeLibrary(as: session)
            var report = Report()

            logger.info("litres library holds \(books.count)")

            for (index, book) in books.enumerated() {
                stage = .working(done: index, total: books.count, title: book.title)

                guard handled.insert(book.id).inserted else { continue }

                do {
                    try await bring(book, as: session, into: &report)
                } catch LitresSyncError.noReadableFile {
                    report.notBooks += 1
                    skipped.append(
                        Failure(id: book.id, title: book.title, reason: "no FB2 offered, art_type \(book.artType)")
                    )
                } catch {
                    report.failed += 1

                    let reason = String(describing: error)

                    failures.append(Failure(id: book.id, title: book.title, reason: reason))
                    logger.error("litres art \(book.id) failed: \(reason, privacy: .public)")
                }
            }

            stage = .done(report)
            announce()
        } catch {
            logger.error("litres library failed: \(String(describing: error), privacy: .public)")
            stage = .failed(Self.describe(error))
            // Books may well have arrived before it stopped, and the shelf should show them.
            announce()
        }
    }

    /// Brings one book across, where it is not already here and current.
    private func bring(_ book: LitresArt, as session: LitresSession, into report: inout Report) async throws {
        let held = await store.localBook(source: .litres, sourceId: String(book.id))

        if let held, !held.isBehind(book.updatedAt) {
            report.alreadyHere += 1
            return
        }

        guard
            let file = try await client.files(of: book.id, as: session).first(where: { $0.format == Self.wanted })
        else { throw LitresSyncError.noReadableFile }

        let archive = try await client.download(art: book.id, file: file, as: session)
        let read = try await BookImporting.read(archive)

        // The same book may already be here under another name, carried in by hand before it was ever
        // synchronised. Its own text is what says so, whatever it arrived in.
        if held == nil, await store.localBook(contentHash: BookInstaller.hash(read.source)) != nil {
            report.alreadyHere += 1
            return
        }

        let installed = await BookImporting.install(
            read,
            origin: BookOrigin(
                source: .litres,
                sourceId: String(book.id),
                updatedAt: book.updatedAt,
                archive: archive,
                // Filed under the service's own name for it, which is steadier than a title and an
                // author: those two are shared by every edition of one book.
                fingerprint: Self.fingerprint(art: book.id)
            ),
            store: store
        )

        guard
            held == nil
        else {
            report.updated += 1
            broughtAcross += 1
            return
        }

        // A book bought and brought across is one the reader has already been through, so it arrives
        // read. Only on the way in: a book being brought across again because the service edited it
        // keeps whatever the reader has since done with it.
        await store.store(progress: 1, workId: installed.id, dated: false)
        report.added += 1
        broughtAcross += 1
    }

    static func fingerprint(art identifier: Int) -> String { "litres:art:\(identifier)" }

    /// Tells the rest of the app the shelf has moved.
    ///
    /// Once a run rather than once a book: reading the whole library back after each of five hundred
    /// arrivals would cost more than the downloads did. A run that stopped partway still says so,
    /// since whatever arrived before it stopped is on the shelf.
    private func announce() {
        guard broughtAcross > 0 else { return }

        BookInbox.shared.libraryChanged()
    }

    /// True where a run has left anything worth reading about.
    var hasSomethingToReport: Bool { !failures.isEmpty || !skipped.isEmpty }

    /// The whole run written out, for a reader who wants to know what "258 failed" was made of.
    func report() -> String {
        var lines = [ "Litres synchronisation, \(Date.now.formatted(.iso8601))" ]

        if case let .done(report) = stage {
            lines.append(
                "added \(report.added), updated \(report.updated), already here \(report.alreadyHere), "
                    + "failed \(report.failed), not readable \(report.notBooks)"
            )
        }

        if case let .failed(reason) = stage { lines.append("the run stopped: \(reason)") }

        lines.append("")
        lines.append("failed (\(failures.count)):")
        lines.append(contentsOf: failures.map { "  \($0.id)  \($0.title) — \($0.reason)" })
        lines.append("")
        lines.append("not readable (\(skipped.count)):")
        lines.append(contentsOf: skipped.map { "  \($0.id)  \($0.title) — \($0.reason)" })
        return lines.joined(separator: "\n")
    }

    /// The report as a file, for sharing off the device.
    func writeReport() -> URL? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("litres-sync.txt")

        do {
            try report().write(to: file, atomically: true, encoding: .utf8)
            return file
        } catch {
            logger.error("could not write the report: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// The one format worth fetching: the app reads FB2 and nothing else.
    private static let wanted = "fb2.zip"

    private static func describe(_ error: Error) -> String {
        switch error {
            case LitresError.unauthorised, LitresError.notSignedIn:
                String(localized: "The session ran out. Sign in again.")
            case LitresError.guarded:
                String(localized: "Litres answered with a challenge rather than an answer.")
            case LitresError.malformed:
                String(localized: "Litres answered with something unexpected.")
            case let LitresError.service(status):
                String(localized: "Litres answered \(status).")
            default:
                error.localizedDescription
        }
    }
}

enum LitresSyncError: Error, LocalizedError {
    case noReadableFile

    var errorDescription: String? {
        switch self {
            case .noReadableFile: String(localized: "No FB2 to download.")
        }
    }
}
