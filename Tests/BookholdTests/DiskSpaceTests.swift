//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookStorage
import Foundation
import Testing

@testable import Bookhold

/// How much room the app says its books take, which has to be room rather than characters.
struct DiskSpaceTests {
    /// A thousand Cyrillic characters are two thousand bytes. Counting the characters and calling them
    /// bytes reported a library of Russian books at half its size.
    @Test
    func russianTextTakesTwoBytesACharacter() throws {
        let folder = try Self.folder()
        let file = folder.appendingPathComponent("chapter.txt")
        let text = String(repeating: "я", count: 1000)

        try Data(text.utf8).write(to: file)

        #expect(text.count == 1000)
        #expect(DiskSpace.taken(by: file) >= 2000)
    }

    @Test
    func aFolderTakesEverythingUnderIt() throws {
        let folder = try Self.folder()
        let inside = folder.appendingPathComponent("Books", isDirectory: true)

        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)

        for name in [ "one", "two" ] {
            try Data(repeating: 0x61, count: 5000).write(to: inside.appendingPathComponent(name))
        }

        #expect(DiskSpace.taken(by: folder) >= 10000)
    }

    @Test
    func somewhereWithNothingInItTakesNothing() throws {
        #expect(DiskSpace.taken(by: try Self.folder()) == 0)
        #expect(DiskSpace.taken(by: URL(fileURLWithPath: "/no/such/file")) == 0)
    }

    private static func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        return folder
    }
}
