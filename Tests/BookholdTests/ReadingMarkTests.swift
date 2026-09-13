//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import DesignSystem
import Foundation
import Testing

@testable import Bookhold

/// Which bookmark a cover carries, where it stands, and the dates that decide both.
///
/// The books are generated: only how far each is read, whether its author has finished and when it was
/// read or taken down matter here.
struct ReadingMarkTests {
    // MARK: - The bookmark

    @Test
    func aBookPartReadCarriesItsPercentage() {
        let mark = ReadingMark(Self.book(read: 0.47, isFinished: true))

        #expect(mark?.kind == .reading)
        #expect(mark?.face == .figure(47))
    }

    /// Never a figure of 0 once started, and never 100 while anything is left.
    @Test(arguments: [ (0.001, 1), (0.994, 99) ])
    func aFigureStaysInsideItsEnds(read: Double, shown: Int) {
        #expect(ReadingMark(Self.book(read: read, isFinished: true))?.face == .figure(shown))
    }

    @Test
    func aBookStillBeingWrittenWaitsWithAPencilAtEitherEnd() {
        let unstarted = ReadingMark(Self.book(read: 0, isFinished: false))
        let caughtUp = ReadingMark(Self.book(read: 1, isFinished: false))

        #expect(unstarted?.kind == .waiting)
        #expect(unstarted?.reached == 0)
        #expect(caughtUp?.kind == .waiting)
        #expect(caughtUp?.reached == 1)
    }

    @Test
    func aFinishedBookReadTodayIsTicked() {
        let mark = ReadingMark(Self.book(read: 1, isFinished: true, readAt: .now.addingTimeInterval(-3600)))

        #expect(mark?.kind == .read)
    }

    @Test
    func aFinishedBookReadLongAgoOrNeverStartedCarriesNothing() {
        #expect(ReadingMark(Self.book(read: 1, isFinished: true, readAt: Self.twoDaysAgo)) == nil)
        #expect(ReadingMark(Self.book(read: 0, isFinished: true)) == nil)
    }

    /// A list that isn't about the reader's progress still says the author is writing.
    @Test
    func aListWithoutProgressKeepsOnlyThePencil() {
        #expect(ReadingMark(Self.book(read: 0.5, isFinished: true), showsProgress: false) == nil)
        #expect(ReadingMark(Self.book(read: 0.5, isFinished: false), showsProgress: false)?.reached == 0)
    }

    // MARK: - Where it stands

    /// Neither end hangs its bookmark on a corner: both stand a little in from the cover's edges.
    @Test
    func theBookmarkStandsOffBothEndsOfTheCover() {
        let width: CGFloat = 90

        #expect(BookmarkMark.offset(reached: 0, across: width) == Design.Space.small)
        #expect(
            BookmarkMark.offset(reached: 1, across: width)
                == width - Design.Size.bookmark - Design.Space.extraSmall
        )
    }

    /// The mark ends where the bookmark does, whatever has been read.
    @Test
    func theLineStopsAtTheBookmark() {
        let width: CGFloat = 90
        let mark = BookmarkMark.silhouette(reached: 1, across: width)

        #expect(mark.boundingBox.maxX == width - Design.Space.extraSmall)
    }

    /// The line runs from the cover's own edge, with the bookmark hanging just past its end.
    @Test
    func theBookmarkHangsPastTheLineRead() {
        let width: CGFloat = 101

        #expect(BookmarkMark.line(reached: 0.1, across: width) == width * 0.1)
        #expect(BookmarkMark.offset(reached: 0.1, across: width) == width * 0.1)
    }

    // MARK: - The day after

    @Test
    func aBookReadTodayStaysUnderReading() {
        let today = Self.book(read: 1, isFinished: true, readAt: .now)
        let before = Self.book(read: 1, isFinished: true, readAt: Self.twoDaysAgo)

        #expect(LibraryScreen.Model.Filter.reading.includes(today))
        #expect(!LibraryScreen.Model.Filter.reading.includes(before))
    }

    // MARK: - The dates the store keeps

    @Test
    func reachingTheEndDatesTheBookUnlessItArrivedRead() async throws {
        let store = try Self.store()

        await store.replaceLibrary(with: [ Self.book(id: 1, read: 0.5), Self.book(id: 2, read: 0.5) ])
        await store.store(progress: 1, workId: 1)
        await store.store(progress: 1, workId: 2, dated: false)

        #expect(await store.book(id: 1)?.summary.readAt != nil)
        #expect(await store.book(id: 2)?.summary.readAt == nil)
    }

    @Test
    func onlyBooksArrivingAfterTheFirstLibraryAreTakenDown() async throws {
        let store = try Self.store()

        await store.replaceLibrary(with: [ Self.book(id: 1, read: 0) ])
        await store.replaceLibrary(with: [ Self.book(id: 1, read: 0), Self.book(id: 2, read: 0) ])

        #expect(await store.book(id: 1)?.summary.takenDownAt == nil)
        #expect(await store.book(id: 2)?.summary.takenDownAt != nil)
    }

    @Test
    func askingForABookTakesItDown() async throws {
        let store = try Self.store()

        await store.replaceLibrary(with: [ Self.book(id: 1, read: 0) ])
        await store.takeDown(workId: 1)

        #expect(await store.book(id: 1)?.summary.takenDownAt != nil)
    }

    // MARK: - Books to test with

    private static let twoDaysAgo = Date.now.addingTimeInterval(-2 * Book.standingOut)

    private static func store() throws -> SQLiteBookStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        return SQLiteBookStore(fileURL: folder.appendingPathComponent("library.sqlite"))
    }

    private static func book(id: Int = 1, read: Double, isFinished: Bool = true, readAt: Date? = nil) -> Book {
        Book(
            id: id,
            title: "Книга",
            authorLine: "Автор",
            coverURL: nil,
            annotation: nil,
            textLength: 1000,
            isFinished: isFinished,
            readingProgress: read,
            hasStartedReading: read > 0,
            libraryState: .reading,
            readAt: readAt
        )
    }
}
