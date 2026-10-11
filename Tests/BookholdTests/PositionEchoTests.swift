//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import Foundation
import Testing

@testable import Bookhold

/// Which of the positions the service holds the library takes over the device's own.
///
/// The service keeps what this app reports and dates it a moment after the device wrote its own, so the
/// newer of the two is not always reading done somewhere else.
@MainActor
struct PositionEchoTests {
    private static let written = Date(timeIntervalSince1970: 1_000_000)
    private static let mine = ReadingPosition(workId: 1, chapterId: 7, characterOffset: 900, updatedAt: written)
    private static let sent = ReportedPosition(workId: 1, chapterId: 7, chapterProgress: 1)

    @Test
    func theDevicesOwnReportComingBackLeavesThePositionAlone() {
        let adopts = LibraryScreen.Model.adopts(
            chapterId: 7,
            percent: 100,
            readAt: Self.written.addingTimeInterval(1.2),
            over: Self.mine,
            sent: Self.sent
        )

        #expect(!adopts, "the last page was given up for the service's copy of it")
    }

    @Test
    func readingDoneElsewhereIsTakenUp() {
        let later = Self.written.addingTimeInterval(3600)

        #expect(LibraryScreen.Model.adopts(chapterId: 7, percent: 40, readAt: later, over: Self.mine, sent: Self.sent))
        #expect(LibraryScreen.Model.adopts(chapterId: 8, percent: 100, readAt: later, over: Self.mine, sent: Self.sent))
        #expect(LibraryScreen.Model.adopts(chapterId: 7, percent: 100, readAt: later, over: Self.mine, sent: nil))
    }

    @Test
    func anOlderPositionIsNeverTakenUp() {
        let earlier = Self.written.addingTimeInterval(-60)

        #expect(!LibraryScreen.Model.adopts(chapterId: 8, percent: 40, readAt: earlier, over: Self.mine, sent: nil))
    }

    @Test
    func whatWasReportedIsKeptAndGoesWithTheBook() async {
        let store = SQLiteBookStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("echo-\(UUID()).sqlite")
        )

        await store.store(reported: Self.sent)
        await store.store(reported: ReportedPosition(workId: 1, chapterId: 8, chapterProgress: 0.25))

        #expect(await store.reported(workId: 1) == ReportedPosition(workId: 1, chapterId: 8, chapterProgress: 0.25))

        await store.removeBook(id: 1)

        #expect(await store.reported(workId: 1) == nil)
    }
}
