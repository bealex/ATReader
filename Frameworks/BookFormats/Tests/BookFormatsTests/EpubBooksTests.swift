//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import Foundation
import Testing

@testable import BookFormats

/// Whatever EPUB files stand in `Fixtures/Books`, read on every run.
///
/// The directory is never committed, so this checks the shape of what comes out rather than any of its
/// words: how many chapters a book has, that each of them carries text, that the pictures it points at
/// are the pictures it holds. A book that reads at all is worth more than an assertion about a book
/// nobody else can see.
struct EpubBooksTests {
    @Test
    func readsEveryBookOnHand() throws {
        let books = Self.files

        guard !books.isEmpty else { return }

        for url in books {
            let parsed = try EpubFormat.parse(Data(contentsOf: url))

            #expect(!parsed.sections.isEmpty, "\(url.lastPathComponent) has no chapters")
            #expect(!parsed.title.isEmpty)

            let text = parsed.sections.reduce(0) { $0 + $1.textLength }

            #expect(text > 1000, "\(url.lastPathComponent) came out with \(text) characters")

            // Every picture a chapter points at has to be one the book brought with it, or the reader
            // drops the block and leaves a hole where the plate was.
            for section in parsed.sections {
                for source in Self.pictures(in: section.html) {
                    #expect(parsed.images[source] != nil, "\(url.lastPathComponent) is missing \(source)")
                }
            }

            // A chapter of nothing is a row in the contents that opens on a blank page.
            for section in parsed.sections {
                #expect(section.textLength > 0 || section.html.contains("<img"))
            }
        }
    }

    /// Prints what each book on hand came out as, which is how a change to the reduction is looked at.
    @Test
    func describesEveryBookOnHand() throws {
        for url in Self.files {
            let parsed = try EpubFormat.parse(Data(contentsOf: url))
            let links = Self.count(of: Self.linkNeedle, in: parsed)
            let anchors = Self.count(of: "data-anchor=", in: parsed)

            print(
                """

                \(url.lastPathComponent)
                  title      \(parsed.title)
                  authors    \(parsed.authors.joined(separator: ", "))
                  language   \(parsed.language ?? "—")
                  identifier \(parsed.identifier ?? "—")
                  series     \(parsed.series ?? "—") \(parsed.seriesOrder.map(String.init) ?? "")
                  cover      \(parsed.cover.map { "\($0.count) bytes" } ?? "—")
                  pictures   \(parsed.images.count)
                  chapters   \(parsed.sections.count)
                  links      \(links)
                  anchors    \(anchors)
                  characters \(parsed.sections.reduce(0) { $0 + $1.textLength })
                """
            )

            for section in parsed.sections.prefix(12) {
                let indent = String(repeating: "  ", count: section.level)

                print("    \(indent)[\(section.level)] \(section.title ?? "—") · \(section.textLength)")
            }

            if parsed.sections.count > 12 { print("    … \(parsed.sections.count - 12) more") }
        }
    }

    // MARK: - The books themselves

    /// The fixtures directory, found from this file rather than from wherever a run was started.
    private static var files: [URL] {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Books", isDirectory: true)

        let found = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)

        return (found ?? []).filter { $0.pathExtension.lowercased() == "epub" }.sorted { $0.path < $1.path }
    }

    /// What a link into the book is written as, kept out of the interpolation above it.
    private static let linkNeedle = "href=\"#"

    /// How often something appears across the whole book, for looking at what a reduction produced.
    private static func count(of needle: String, in book: ParsedBook) -> Int {
        book.sections.reduce(0) { $0 + $1.html.components(separatedBy: needle).count - 1 }
    }

    private static func pictures(in html: String) -> [String] {
        var found: [String] = []
        var cursor = html.startIndex

        while let open = html.range(of: "<img src=\"", range: cursor ..< html.endIndex) {
            let source = html[open.upperBound...].prefix { $0 != "\"" }

            found.append(String(source))
            cursor = open.upperBound
        }

        return found
    }
}
