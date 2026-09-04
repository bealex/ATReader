//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import Testing
import UIKit

@testable import ATReader

/// An illustrated FB2 taken all the way through: read in, written out, laid out and drawn.
///
/// No book belongs in this repository, so the file is named in the environment and these do nothing
/// without it. `AT_TEST_BOOK` is the path to an FB2; `AT_RENDER_DIR` is where the pages carrying
/// pictures are written, one PNG per theme, for looking at.
///
///     TEST_RUNNER_AT_TEST_BOOK=~/Books/illustrated.fb2 \
///     TEST_RUNNER_AT_RENDER_DIR=$PWD/build/renders Scripts/app.sh test --only ATReaderTests
@MainActor
struct IllustratedBookTests {
    private static var path: String? { ProcessInfo.processInfo.environment["AT_TEST_BOOK"] }
    private static var renderDirectory: String? { ProcessInfo.processInfo.environment["AT_RENDER_DIR"] }

    /// The themes a picture has to look right in: paper, the darkest of the dark ones, and green,
    /// whose foreground sits halfway up and so stretches the mapping hardest.
    private static let themes: [ReaderSettings.Theme] = [ .paper, .night, .green ]

    @Test
    func keepsThePicturesTheTextPointsAt() async throws {
        guard let book = try await parse() else { return }

        #expect(!book.images.isEmpty)
        // Every picture kept is one the text asked for, and every one asked for is here.
        #expect(Set(book.images.keys) == Set(Self.referenced(in: book)))
    }

    @Test
    func setsThePicturesIntoTheColumn() async throws {
        guard let imported = try await open() else { return }

        let withPictures = imported.chapters.filter { $0.content.imageSources.isEmpty == false }

        #expect(!withPictures.isEmpty)

        for chapter in withPictures.prefix(4) {
            let layout = await Self.layout(chapter, theme: .paper)
            let drawn = layout.typesetLines.filter(\.isImage)

            #expect(drawn.count == chapter.content.imageSources.count)
            #expect(drawn.allSatisfy { $0.width > 0 })
        }
    }

    /// A picture never runs off the foot of the page it lands on.
    @Test
    func keepsEveryPictureOnItsPage() async throws {
        guard let imported = try await open() else { return }

        for chapter in imported.chapters.filter({ !$0.content.imageSources.isEmpty }).prefix(4) {
            let context = Self.context(theme: .paper)
            let layout = await Self.layout(chapter, theme: .paper)

            for page in 0 ..< layout.pageCount {
                let lines = layout.typesetLines(onPage: page)
                let depth = lines.reduce(CGFloat(0)) { $0 + $1.height }
                // A page may pull its gaps in to take one more line, so it can stand a little deeper
                // than its measure before anything is actually running off it.
                let squeeze = CGFloat(max(0, lines.count - 1)) * ChapterLayout.Rules.tightening

                #expect(depth <= context.textSize.height + squeeze + 1)
            }
        }
    }

    /// The pages carrying pictures, drawn in each theme so the ink rule can be looked at.
    @Test
    func drawsThePagesWithPicturesInEveryTheme() async throws {
        guard let directory = Self.renderDirectory, let imported = try await open() else { return }

        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        for monochrome in [ false, true ] {
            for theme in Self.themes {
                try await write(imported, theme: theme, monochrome: monochrome, to: directory)
            }
        }
    }

    private func write(
        _ imported: Imported,
        theme: ReaderSettings.Theme,
        monochrome: Bool,
        to directory: String
    ) async throws {
        let context = Self.context(theme: theme, monochrome: monochrome)
        var written = 0

        for chapter in imported.chapters where !chapter.content.imageSources.isEmpty {
            guard written < 3 else { return }

            let layout = await Self.layout(chapter, theme: theme, monochrome: monochrome)
            let pages = (0 ..< layout.pageCount).filter { page in
                layout.typesetLines(onPage: page).contains { $0.isImage }
            }

            for page in pages.prefix(1) {
                let label = "\(theme.rawValue)\(monochrome ? "-mono" : "")-c\(chapter.position)-p\(page + 1)"
                let image = Self.draw(page: page, of: layout, context: context, theme: theme)

                try image.pngData()?.write(
                    to: URL(fileURLWithPath: directory).appendingPathComponent("picture-\(label).png")
                )
                written += 1
            }
        }
    }

    /// The path the device actually takes: prepared text stored as JSON and read back on the next open.
    ///
    /// Everything else here parses a chapter and lays it out in one breath. The reader doesn't. It reads
    /// what `BookProcessor` stored, so a picture has to survive a round trip through `Codable` that no
    /// other test crosses.
    @Test
    func keepsPicturesThroughTheStore() async throws {
        guard let opened = try await importBook() else { return }

        let processor = BookProcessor(store: opened.store)
        var chapters: [Chapter] = []

        for (position, chapter) in await opened.store.chapters(workId: opened.workId).enumerated() {
            // Twice on purpose: the first call prepares and stores, the second reads back what it wrote.
            _ = await processor.content(workId: opened.workId, chapterId: chapter.id)

            guard
                let content = await processor.content(workId: opened.workId, chapterId: chapter.id)
            else { continue }

            chapters.append(Chapter(position: position + 1, title: chapter.title, content: content))
        }

        let withPictures = chapters.filter { !$0.content.imageSources.isEmpty }

        #expect(!withPictures.isEmpty)

        guard let directory = Self.renderDirectory, let first = withPictures.first else { return }

        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let layout = await Self.layout(first, theme: .paper)
        let pages = (0 ..< layout.pageCount).filter { page in
            layout.typesetLines(onPage: page).contains { $0.isImage }
        }

        #expect(!pages.isEmpty)

        for page in pages.prefix(1) {
            let image = Self.draw(
                page: page,
                of: layout,
                context: Self.context(theme: .paper),
                theme: .paper
            )
            try image.pngData()?.write(
                to: URL(fileURLWithPath: directory)
                    .appendingPathComponent("stored-c\(first.position)-p\(page + 1).png")
            )
        }
    }

    // MARK: - Reading the book in

    private struct Chapter {
        var position: Int
        var title: String?
        var content: ChapterContent
    }

    private struct Imported {
        var chapters: [Chapter]
    }

    private func parse() async throws -> FB2Book? {
        guard
            let path = Self.path,
            let data = try? Data(contentsOf: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        else { return nil }

        // The named file may be an archive, since that is how these books are usually handed out.
        return try FB2Parser.parse(ZipArchive.isArchive(data) ? ZipArchive.book(in: data) : data)
    }

    /// A book read into a store of its own.
    private struct Opened {
        var store: LocalStore
        var workId: Int
    }

    private func importBook() async throws -> Opened? {
        guard let path = Self.path else { return nil }

        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)

        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("illustrated-\(UUID().uuidString).sqlite")
        let store = LocalStore(fileURL: file)
        let work = try await BookImport.import(from: url, store: store)

        return Opened(store: store, workId: work.id)
    }

    /// Imports the book, then reads back what the reader would read.
    private func open() async throws -> Imported? {
        guard let opened = try await importBook() else { return nil }

        var chapters: [Chapter] = []

        for (position, chapter) in await opened.store.chapters(workId: opened.workId).enumerated() {
            guard
                let body = await opened.store.body(workId: opened.workId, chapterId: chapter.id)
            else { continue }

            chapters.append(Chapter(
                position: position + 1,
                title: chapter.title,
                content: await ChapterContent.prepare(html: body.html)
            ))
        }

        return Imported(chapters: chapters)
    }

    /// The names every `<image>` in the book's text asked for.
    private static func referenced(in book: FB2Book) -> [String] {
        book.sections
            .flatMap { ChapterHTML.paragraphs(from: $0.html) }
            .compactMap(\.imageSource)
            .reduce(into: Set<String>()) { $0.insert($1) }
            .sorted()
    }

    // MARK: - Laying it out

    private static func context(
        theme: ReaderSettings.Theme,
        monochrome: Bool = false
    ) -> ChapterLayout.Context {
        var context = JustificationTests.testContext
        context.style.textColor = UIColor(theme.foreground)
        context.style.backgroundColor = UIColor(theme.background)
        context.style.monochromeImages = monochrome
        return context
    }

    private static func layout(
        _ chapter: Chapter,
        theme: ReaderSettings.Theme,
        monochrome: Bool = false
    ) async -> ChapterLayout {
        await ChapterLayout.make(
            chapterId: chapter.position,
            content: chapter.content,
            heading: ChapterHeading.make(position: chapter.position, title: chapter.title),
            context: context(theme: theme, monochrome: monochrome)
        )
    }

    private static func draw(
        page: Int,
        of layout: ChapterLayout,
        context: ChapterLayout.Context,
        theme: ReaderSettings.Theme
    ) -> UIImage {
        UIGraphicsImageRenderer(size: context.pageSize).image { drawing in
            UIColor(theme.background).setFill()
            drawing.fill(CGRect(origin: .zero, size: context.pageSize))
            layout.draw(page: page)
        }
    }
}
