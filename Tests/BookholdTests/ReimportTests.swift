//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookFormats
import BookKit
import BookRenderer
import BookStorage
import Foundation
import Testing

@testable import Bookhold

/// Reading a book's own file again, for one imported before the parser knew something it knows now.
///
/// The book is written for the test. What matters is where it lands: a book a service handed over is
/// filed under the service's name for it, and working a name out from its file again names it something
/// else, which stands the same book on the shelf twice instead of correcting the one already there.
@MainActor
struct ReimportTests {
    private static let file = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
          <description>
            <title-info><book-title>Проба</book-title></title-info>
            <document-info><id>c420b97e</id></document-info>
          </description>
          <body>
            <section><title><p>Одна</p></title><p>Раз.</p></section>
            <section><title><p>Другая</p></title><p>Два.</p></section>
          </body>
        </FictionBook>
        """.utf8)

    private func store() -> SQLiteBookStore {
        SQLiteBookStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("reimport-\(UUID()).sqlite")
        )
    }

    /// A book the way Litres hands one over: filed under the service's own name for it.
    private func installed(into store: SQLiteBookStore) async throws -> Book {
        let read = try await BookImporting.read(Self.file)

        return await BookImporting.install(
            read,
            origin: BookOrigin(
                source: .litres,
                sourceId: "125559",
                archiveHash: "anarchive",
                fingerprint: "litres:art:125559"
            ),
            store: store
        )
    }

    @Test
    func landsOnTheBookItReadAgain() async throws {
        let store = store()
        let book = try await installed(into: store)
        let again = try await BookImporting.reimport(workId: book.id, store: store)

        #expect(again.id == book.id, "the book was stood on the shelf a second time")
        #expect(await store.localBooks().count == 1)
    }

    /// And it stays the service's book: re-reading its file doesn't turn it into a book off a file.
    @Test
    func keepsWhatTheBookIsFiledUnder() async throws {
        let store = store()
        let book = try await installed(into: store)

        _ = try await BookImporting.reimport(workId: book.id, store: store)

        let held = try #require(await store.localBook(workId: book.id))

        #expect(held.source == .litres)
        #expect(held.sourceId == "125559")
        #expect(held.fingerprint == "litres:art:125559")
        #expect(held.archiveHash == "anarchive")
    }

    /// A book read by this build is dated with what this build makes of a file, which is what says
    /// later whether it has to be read again.
    @Test
    func datesWhatThisBuildMadeOfTheFile() async throws {
        let store = store()
        let book = try await installed(into: store)
        let held = try #require(await store.localBook(workId: book.id))

        #expect(held.readingVersion == BookReading.version)
        #expect(!held.isBehindThisBuild)
    }

    /// One read by a build that made less of the same file is read again, and dated afresh.
    @Test
    func readsAgainWhateverIsBehindThisBuild() async throws {
        let store = store()
        let book = try await installed(into: store)
        let held = try #require(await store.localBook(workId: book.id))

        await store.store(provenance: LocalBookRecord(
            workId: held.workId,
            fingerprint: held.fingerprint,
            source: held.source,
            sourceId: held.sourceId,
            contentHash: held.contentHash,
            readingVersion: BookReading.version - 1
        ))

        #expect(await store.localBook(workId: book.id)?.isBehindThisBuild == true)

        // Installing keeps the file, which is the whole reason a book can be read again at all.
        #expect(LocalBookFiles.hasKeptFile(workId: book.id))

        defer { try? FileManager.default.removeItem(at: LocalBookFiles.fileURL(workId: book.id)) }

        let inbox = BookInbox(store: store, processor: BookProcessor(store: store))

        #expect(await inbox.rereadWhatIsBehind() == 1)
        #expect(await store.localBook(workId: book.id)?.readingVersion == BookReading.version)
        #expect(await store.localBooks().count == 1, "the book was stood on the shelf a second time")
    }

    /// A book already up to date is left alone.
    @Test
    func leavesAloneWhateverThisBuildAlreadyRead() async throws {
        let store = store()
        let inbox = BookInbox(store: store, processor: BookProcessor(store: store))

        _ = try await installed(into: store)

        #expect(await inbox.rereadWhatIsBehind() == 0)
    }

    /// Reading a file again is not the book changing, so nothing about where it stands moves.
    @Test
    func leavesTheBookStandingWhereItStood() async throws {
        let store = store()
        let book = try await installed(into: store)
        let held = try #require(await store.book(id: book.id)?.summary)
        let when = Date.now.addingTimeInterval(-7 * 24 * 3600)
        var settled = Book(
            id: held.id,
            title: held.title,
            authorLine: held.authorLine,
            coverURL: held.coverURL,
            annotation: held.annotation,
            textLength: held.textLength,
            isFinished: true,
            lastUpdateTime: when,
            readingProgress: 1,
            hasStartedReading: true,
            lastReadTime: when,
            libraryState: .finished
        )

        settled.readAt = when
        await store.store(book: settled)

        _ = try await BookImporting.reimport(workId: book.id, store: store)

        let after = try #require(await store.book(id: book.id)?.summary)

        #expect(after.libraryState == .finished)
        #expect(after.readingProgress == 1)
        // Neither of the dates that put a book out as a cover moves: a book read to its end a week ago
        // is not one read just now.
        #expect(after.readAt == held.readAt)
        #expect(after.takenDownAt == held.takenDownAt)
        #expect(
            after.lastUpdateTime.map { abs($0.timeIntervalSince(when)) < 1 } == true,
            "the book was dated as changed today, which shuffles the library under the reader"
        )
    }

    /// A re-read never moves the reader nearer the front of a book than they were.
    ///
    /// What went wrong: a chapter the store had never measured counted as nothing, so the place came
    /// out as the offset into its own chapter and the reader was put back in chapter one.
    @Test
    func leavesThePositionAloneWhereTheBookWasNeverMeasured() async throws {
        let store = store()
        let book = try await installed(into: store)
        let chapters = await store.chapters(workId: book.id)
        let last = try #require(chapters.last)

        // Chapters as a build that did not measure them left them behind.
        await store.store(
            chapters: chapters.map {
                BookChapter(
                    id: $0.id,
                    workId: $0.workId,
                    title: $0.title,
                    sortOrder: $0.sortOrder,
                    textLength: nil,
                    level: $0.level
                )
            },
            workId: book.id
        )
        await store.store(position: .init(workId: book.id, chapterId: last.id, characterOffset: 12, updatedAt: .now))

        _ = try await BookImporting.reimport(workId: book.id, store: store)

        let place = try #require(await store.position(workId: book.id))

        #expect(place.chapterId == last.id, "the reader was carried back to the front of the book")
        #expect(place.characterOffset == 12)
    }

    /// A cover written down under a container the system has since renamed is found all the same.
    ///
    /// The app is given a new container every time it is installed, so the path a book's cover was
    /// written down under names a directory that is no longer there: every local book would lose its
    /// artwork, and with it the spine that is a blur of that artwork.
    @Test
    func findsACoverTheSystemMovedTheContainerOf() async throws {
        let store = store()
        let book = try await installed(into: store)
        let held = try #require(await store.book(id: book.id)?.summary)
        let stale = Book(
            id: held.id,
            title: held.title,
            authorLine: held.authorLine,
            coverURL: URL(fileURLWithPath: "/var/mobile/Containers/Data/Application/GONE/Books/1.cover.jpeg"),
            annotation: held.annotation,
            textLength: held.textLength,
            libraryState: held.libraryState
        )

        await store.store(book: stale)

        let read = try #require(await store.book(id: book.id)?.summary)

        #expect(read.coverURL == LocalBookFiles.coverURL(workId: book.id))
        #expect(read.coverURL?.path.contains("GONE") != true, "the book kept a container that is gone")
    }

    /// A book that came off a file in the first place is filed the same way it was.
    @Test
    func landsOnABookThatCameFromAFile() async throws {
        let store = store()
        let read = try await BookImporting.read(Self.file)
        let book = await BookImporting.install(read, origin: BookOrigin(source: .file), store: store)
        let again = try await BookImporting.reimport(workId: book.id, store: store)

        #expect(again.id == book.id)
        #expect(await store.localBooks().count == 1)
    }
}
