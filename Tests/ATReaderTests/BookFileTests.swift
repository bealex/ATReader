//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Testing
import UIKit

@testable import ATReader

/// Getting a book off a file: out of an archive, and back out of the copy kept beside it.
///
/// Every book here is generated. The archives are made by the system rather than by this test, so the
/// reader is checked against a real zip instead of against one written to match it.
@MainActor
struct BookFileTests {
    // MARK: - Archives

    @Test
    func readsAnArchiveTheSystemMade() throws {
        let book = Self.fb2()
        let archive = try #require(Self.zipped(book, named: "book.fb2"))

        #expect(ZipArchive.isArchive(archive))
        #expect(try ZipArchive.book(in: archive) == book)
    }

    @Test
    func leavesAPlainFileAlone() {
        #expect(!ZipArchive.isArchive(Self.fb2()))
    }

    /// A zip holding more than the book picks the member that is one.
    @Test
    func findsTheBookBesideOtherFiles() throws {
        let book = Self.fb2()
        let archive = try #require(Self.zipped(
            [ "notes.txt": Data("nothing to read here".utf8), "book.fb2": book ]
        ))

        #expect(try ZipArchive.book(in: archive) == book)
    }

    @Test
    func refusesAnArchiveWithNoBookInIt() throws {
        let archive = try #require(Self.zipped(Data("nothing".utf8), named: "notes.txt"))

        // Nothing names itself a book, so the largest file is taken and the parser turns it down.
        #expect(throws: FB2Error.self) { try FB2Parser.parse(ZipArchive.book(in: archive)) }
    }

    // MARK: - Importing

    @Test
    func importsAZippedBook() async throws {
        let archive = try #require(Self.zipped(Self.fb2(), named: "book.fb2"))
        let imported = try await Self.importing(archive, named: "book.fb2.zip")

        defer { Self.clean(imported) }

        #expect(await imported.store.chapters(workId: imported.workId).count == 1)
    }

    /// A zipped book and the same book unzipped are one book, not two.
    @Test
    func filesAZippedBookWhereThePlainOneWouldGo() async throws {
        let book = Self.fb2()
        let plain = try await Self.importing(book, named: "book.fb2")

        defer { Self.clean(plain) }

        let archive = try #require(Self.zipped(book, named: "book.fb2"))
        let zipped = try await BookImport.import(
            from: Self.written(archive, named: "book.fb2.zip"),
            store: plain.store
        )

        #expect(zipped.id == plain.workId)
    }

    // MARK: - The file kept beside the book

    @Test
    func keepsTheBookItImported() async throws {
        let book = Self.fb2()
        let imported = try await Self.importing(book, named: "book.fb2")

        defer { Self.clean(imported) }

        #expect(LocalBooks.hasKeptFile(workId: imported.workId))
        // Kept compressed, so what comes back has to be the book rather than what was written.
        #expect(LocalBooks.keptFile(workId: imported.workId) == book)
    }

    /// What is kept is the book, not the archive it arrived in.
    @Test
    func keepsTheBookRatherThanTheArchive() async throws {
        let book = Self.fb2()
        let archive = try #require(Self.zipped(book, named: "book.fb2"))
        let imported = try await Self.importing(archive, named: "book.fb2.zip")

        defer { Self.clean(imported) }

        #expect(LocalBooks.keptFile(workId: imported.workId) == book)
    }

    @Test
    func readsTheBookAgainFromWhatItKept() async throws {
        let imported = try await Self.importing(Self.fb2(), named: "book.fb2")

        defer { Self.clean(imported) }

        let again = try await BookImport.reimport(workId: imported.workId, store: imported.store)

        #expect(again.id == imported.workId)
        #expect(await imported.store.chapters(workId: imported.workId).count == 1)
    }

    /// The pictures come back too, which is the whole point of keeping the file.
    @Test
    func bringsThePicturesBackOnASecondReading() async throws {
        let imported = try await Self.importing(Self.fb2(), named: "book.fb2")

        defer { Self.clean(imported) }

        try await BookImport.reimport(workId: imported.workId, store: imported.store)

        let chapters = await imported.store.chapters(workId: imported.workId)
        let body = try #require(await imported.store.body(workId: imported.workId, chapterId: chapters[0].id))
        let content = await ChapterContent.prepare(html: body.html)

        #expect(content.imageSources.count == 1)
        #expect(await !BookImages.shared.prepare(sources: content.imageSources).isEmpty)
    }

    @Test
    func takesTheKeptFileAwayWithTheBook() async throws {
        let imported = try await Self.importing(Self.fb2(), named: "book.fb2")

        await BookImport.remove(workId: imported.workId, store: imported.store)

        #expect(!LocalBooks.hasKeptFile(workId: imported.workId))
    }

    // MARK: - Making a book to read

    /// A book read into a store of its own, and the file it was read from.
    private struct Imported {
        var store: LocalStore
        var workId: Int
        var database: URL
    }

    private static func importing(_ data: Data, named name: String) async throws -> Imported {
        let database = FileManager.default.temporaryDirectory
            .appendingPathComponent("books-\(UUID().uuidString).sqlite")
        let store = LocalStore(fileURL: database)
        let work = try await BookImport.import(from: written(data, named: name), store: store)

        return Imported(store: store, workId: work.id, database: database)
    }

    private static func clean(_ imported: Imported) {
        try? FileManager.default.removeItem(at: imported.database)
        try? FileManager.default.removeItem(at: LocalBooks.fileURL(workId: imported.workId))
        try? FileManager.default.removeItem(at: LocalBooks.imagesDirectory(workId: imported.workId))
        try? FileManager.default.removeItem(at: LocalBooks.coverURL(workId: imported.workId))
    }

    private static func written(_ data: Data, named name: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(name)")

        try? data.write(to: url)
        return url
    }

    /// One file zipped by the system, which is what makes this a test of the reader rather than of a
    /// writer written to match it.
    private static func zipped(_ data: Data, named name: String) -> Data? {
        zipped([ name: data ])
    }

    private static func zipped(_ files: [String: Data]) -> Data? {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("zip-\(UUID().uuidString)", isDirectory: true)

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        for (name, data) in files {
            try? data.write(to: folder.appendingPathComponent(name))
        }

        var coordinated: NSError?
        var archive: Data?

        NSFileCoordinator().coordinate(
            readingItemAt: folder,
            options: [ .forUploading ],
            error: &coordinated
        ) { url in
            archive = try? Data(contentsOf: url)
        }

        return archive
    }

    /// A book with one chapter, a cover and one plate in the text. Nonsense, and its own every time so
    /// two of them never file as one.
    private static func fb2() -> Data {
        let cover = picture(.systemTeal).base64EncodedString()
        let plate = picture(.black).base64EncodedString()
        let book = """
            <?xml version="1.0" encoding="utf-8"?>
            <FictionBook xmlns:l="http://www.w3.org/1999/xlink">
            <description><title-info>
            <book-title>Пример книги</book-title><lang>ru</lang>
            <author><first-name>Имя</first-name><last-name>Фамилия</last-name></author>
            <coverpage><image l:href="#cover.png"/></coverpage>
            </title-info><document-info><id>\(UUID().uuidString)</id></document-info></description>
            <body><section><title><p>Глава первая</p></title>
            <p>Первый выдуманный абзац, написанный только для этой проверки.</p>
            <empty-line/><image l:href="#plate.png"/><empty-line/>
            <p>Второй выдуманный абзац, такой же бессмысленный, как и первый.</p>
            </section></body>
            <binary id="cover.png" content-type="image/png">\(cover)</binary>
            <binary id="plate.png" content-type="image/png">\(plate)</binary>
            </FictionBook>
            """

        return Data(book.utf8)
    }

    private static func picture(_ colour: UIColor) -> Data {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1

        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 26), format: format).image { drawing in
            UIColor.white.setFill()
            drawing.fill(CGRect(x: 0, y: 0, width: 40, height: 26))

            colour.setFill()
            drawing.fill(CGRect(x: 6, y: 4, width: 14, height: 18))
        }

        return image.pngData() ?? Data()
    }
}
