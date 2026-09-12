//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import Foundation
import Testing

@testable import Bookhold

/// What a series' books are called on the shelf, checked against a list the reader corrected by hand.
///
/// The list is real titles, so it lives in `Fixtures/Titles/series-titles.tsv`, which git ignores, and
/// these pass having read nothing where it isn't. One book a line, tab-separated: series, author, the
/// volume the file states, the title, what the shelf showed when the list was written, and what it
/// should show. The last column is the one to edit.
///
/// `AT_BACKUP` with `AT_TITLES_WRITE` set writes the list afresh from a backup, the last two columns
/// both filled with what the shelf shows now.
struct SeriesTitlesTests {
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    private static var list: URL? {
        environment["AT_TITLES"].map { URL(fileURLWithPath: $0).appendingPathComponent("series-titles.tsv") }
    }

    /// One book as the list holds it.
    private struct Line {
        let series: String
        let author: String
        let volume: Int?
        let title: String
        let shown: String
        let expected: String

        var fields: [String] { [ series, author, volume.map(String.init) ?? "", title, shown, expected ] }
    }

    @Test
    @MainActor
    func showsEveryTitleTheWayTheListSays() throws {
        guard let list = Self.list, let text = try? String(contentsOf: list, encoding: .utf8) else { return }

        let lines = text.split(separator: "\n").dropFirst().compactMap(Self.line(of:))
        var wrong: [String] = []

        for (series, held) in Dictionary(grouping: lines, by: { "\($0.series)|\($0.author)" }) {
            let books = held.enumerated().map { index, line in Self.book(line, id: index + 1) }
            let shown = Self.shown(books, series: held[0].series)

            for (index, line) in held.enumerated() where shown[index + 1] != line.expected {
                wrong.append("\(series): \(line.title) → \(shown[index + 1] ?? "") instead of \(line.expected)")
            }
        }

        #expect(wrong.isEmpty, "\(wrong.sorted().joined(separator: "\n"))")
    }

    @Test
    @MainActor
    func writesTheListFromABackup() async throws {
        guard
            Self.environment["AT_TITLES_WRITE"] != nil,
            let backup = Self.environment["AT_BACKUP"],
            let list = Self.list
        else { return }

        let books = await SQLiteBookStore(fileURL: try Self.copied(backup)).books().filter { $0.series != nil }
        var lines: [Line] = []

        for (_, held) in Dictionary(grouping: books, by: { "\($0.series ?? "")|\(Self.lead($0.authorLine))" }) {
            let series = held[0].series ?? ""
            let shown = Self.shown(held, series: series)

            for book in held.sorted(by: { ($0.seriesOrder ?? 0, $0.title) < ($1.seriesOrder ?? 0, $1.title) }) {
                let name = shown[book.id] ?? book.title

                lines.append(Line(
                    series: series,
                    author: Self.lead(book.authorLine),
                    volume: book.seriesOrder,
                    title: book.title,
                    shown: name,
                    expected: name
                ))
            }
        }

        let header = [ "series", "author", "volume", "title", "shown", "expected" ].joined(separator: "\t")
        let body = lines
            .sorted { ($0.series, $0.author, $0.volume ?? 0) < ($1.series, $1.author, $1.volume ?? 0) }
            .map { $0.fields.joined(separator: "\t") }

        try FileManager.default.createDirectory(at: list.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ([ header ] + body).joined(separator: "\n").write(to: list, atomically: true, encoding: .utf8)
    }

    /// With `AT_TITLES_SHELF` and `AT_BACKUP`, writes `shelf-titles.tsv` beside the list: every book in a
    /// series as the library shows it, card by card. Columns: title, series, shown title, the volume the
    /// book states, the one its title gives, the one the shelf shows, and the card.
    @Test
    @MainActor
    func writesWhatTheShelfShows() async throws {
        guard
            Self.environment["AT_TITLES_SHELF"] != nil,
            let backup = Self.environment["AT_BACKUP"],
            let list = Self.list
        else { return }

        let model = LibraryScreen.Model(session: SessionStore(), store: SQLiteBookStore(fileURL: try Self.copied(backup)))

        await model.refreshFromStore()
        model.filter = .everything

        var lines = [
            [ "title", "series", "shown", "stated", "from title", "volume", "card" ].joined(separator: "\t"),
        ]
        let shelves = model.shelves.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        for shelf in shelves {
            for group in shelf.runs + shelf.alone {
                for slot in model.slots(of: group) {
                    guard case let .book(work, number, title, _) = slot, let series = group.series ?? work.series else {
                        continue
                    }

                    let titled = group.numbering?.books.first { $0.book.id == work.id }?.number
                    let fields = [ work.title, series, title ] + [ work.seriesOrder, titled, number ].map { $0.map(String.init) ?? "" }

                    lines.append((fields + [ shelf.name ]).joined(separator: "\t"))
                }
            }
        }

        let shown = list.deletingLastPathComponent().appendingPathComponent("shelf-titles.tsv")

        try lines.joined(separator: "\n").write(to: shown, atomically: true, encoding: .utf8)
    }

    /// A copy of the backup's library to read, so nothing a test does reaches the backup itself.
    private static func copied(_ backup: String) throws -> URL {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("titles-\(UUID().uuidString).sqlite")

        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: (backup as NSString).expandingTildeInPath).appendingPathComponent("library.sqlite"),
            to: copy
        )

        return copy
    }

    /// What the shelf calls each of one series' books, by book.
    @MainActor
    private static func shown(_ books: [Book], series: String) -> [Int: String] {
        let ordered = LibraryScreen.Model.ordered(books, arrangedByHand: false)
        let group = LibraryScreen.Model.Group(
            id: "series:\(series)",
            series: series,
            works: ordered,
            updated: .now,
            numbering: SeriesNumbering.read(ordered)
        )

        return group.rows.reduce(into: [:]) { names, row in
            guard case let .book(work, _, title) = row else { return }

            names[work.id] = title
        }
    }

    private static func book(_ line: Line, id: Int) -> Book {
        Book(
            id: id,
            title: line.title,
            authorLine: line.author,
            coverURL: nil,
            annotation: nil,
            seriesTitle: line.series,
            seriesOrder: line.volume
        )
    }

    private static func line(of text: Substring) -> Line? {
        let fields = text.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)

        guard fields.count >= 6 else { return nil }

        return Line(
            series: fields[0],
            author: fields[1],
            volume: Int(fields[2]),
            title: fields[3],
            shown: fields[4],
            expected: fields[5]
        )
    }

    private static func lead(_ line: String) -> String {
        String(line.split(separator: ",").first ?? "").trimmingCharacters(in: .whitespaces)
    }
}
