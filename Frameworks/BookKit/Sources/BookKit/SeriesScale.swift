//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// Puts a series held from more than one place on one scale.
///
/// The two count differently. A service gives every volume its own place, so a work running to two
/// volumes takes two; a file gives the work one place however far it runs. A library holding some of
/// a series each way reads as one numbering with gaps in it and two books standing on one place.
///
/// What comes out is the way a series is printed: a work has one place and its volumes share it. A
/// work the reader doesn't hold is taken to run to a single volume, that being the one thing nothing
/// on the device can answer.
public enum SeriesScale {
    /// Every book's volume, keyed by book, for a whole library at once: the place its work stands on,
    /// which the work's volumes share. A book that states no place, or belongs to no series, is left out.
    public static func volumes(of books: [Book]) -> [Int: Int] {
        read(books) { $0.shared }
    }

    /// Every book's own place, each volume counted apart.
    ///
    /// Two copies of one volume come out alike however either was numbered, and two volumes of one
    /// work come out different, which is what ``volumes(of:)`` deliberately throws away.
    public static func volumesApart(of books: [Book]) -> [Int: Int] {
        read(books) { $0.apart }
    }

    private static func read(_ books: [Book], _ wanted: (Numbering) -> [Int: Int]) -> [Int: Int] {
        Dictionary(grouping: books) { $0.series }
            .reduce(into: [:]) { volumes, each in
                guard each.key != nil else { return }

                for (id, volume) in wanted(numbered(each.value)) { volumes[id] = volume }
            }
    }

    /// One series counted both ways at once.
    private struct Numbering {
        var shared: [Int: Int] = [:]
        var apart: [Int: Int] = [:]
    }

    /// One book's own name and every copy of it, however many volumes it runs to.
    private struct Work {
        let key: String
        /// Each copy held, and which volume of the work it is.
        var held: [(id: Int, volume: Int)] = []
        /// The place a file states, a file counting a work as one whatever it runs to.
        var file: Int?
        /// The first place the service states for it, the service counting every volume.
        var service: Int?
        /// The furthest volume any copy names, and the stretch the service's places cover.
        var named = 1
        var covered: (low: Int, high: Int)?

        /// How many volumes the work runs to, as far as anything here can tell.
        var span: Int {
            max(named, covered.map { $0.high - $0.low + 1 } ?? 1)
        }
    }

    private static func numbered(_ books: [Book]) -> Numbering {
        let works = Self.works(in: books)

        return places(of: works, starting: serviceStarts(of: works))
    }

    private static func works(in books: [Book]) -> [Work] {
        var found: [String: Work] = [:]
        var order: [String] = []

        for book in books {
            let (key, volume) = nameAndVolume(of: book.title)
            var work = found[key] ?? Work(key: key)

            if found[key] == nil { order.append(key) }

            work.held.append((book.id, volume))
            work.named = max(work.named, volume)

            if let stated = book.seriesOrder, stated > 0 {
                if BookNumbering.isLocal(book.id) {
                    work.file = min(work.file ?? stated, stated)
                } else {
                    work.service = min(work.service ?? stated, stated)
                    work.covered = (min(work.covered?.low ?? stated, stated), max(work.covered?.high ?? stated, stated))
                }
            }

            found[key] = work
        }

        return order.compactMap { found[$0] }
    }

    /// Every work's first place counted the service's way, which is the one scale both sides meet on.
    ///
    /// A work the service named says where it starts. One known only as a file is placed by walking
    /// the files in order, the volumes ahead of it pushing it along.
    private static func serviceStarts(of works: [Work]) -> [String: Int] {
        var started: [String: Int] = [:]
        var ahead = 0

        for work in works.compactMap({ work in work.file.map { (work, $0) } }).sorted(by: { $0.1 < $1.1 }) {
            started[work.0.key] = work.1 + ahead
            ahead += work.0.span - 1
        }

        // What the service states beats anything walked to: a file's figure is whatever whoever made
        // the file wrote in it, and two files of one series are often made by different hands.
        for work in works {
            guard let service = work.service else { continue }

            started[work.key] = service
        }

        return started
    }

    /// Each book's place, with the volumes that ran ahead of it taken off, so a work's volumes share one.
    private static func places(of works: [Work], starting: [String: Int]) -> Numbering {
        let placed = works.compactMap { work in starting[work.key].map { (work, $0) } }
        var numbering = Numbering()
        var ahead = 0

        for (work, start) in placed.sorted(by: { $0.1 < $1.1 }) {
            let place = max(1, start - ahead)

            for copy in work.held {
                numbering.shared[copy.id] = place
                // Counted the service's way, where a work's second volume stands one past its first.
                numbering.apart[copy.id] = start + copy.volume - 1
            }

            ahead += work.span - 1
        }

        return numbering
    }

    /// What every volume of one work is looked up under, and which volume of the work this title is.
    ///
    /// A title that is nothing but a volume keeps the whole of itself: there would be nothing left to
    /// tell one work from another, and a figure standing alone counts the series rather than the work.
    private static func nameAndVolume(of title: String) -> (name: String, volume: Int) {
        let words = pieces(of: title)
        let kept = withoutVolume(words)

        guard !kept.isEmpty else { return (words.joined(separator: " "), 1) }

        return (kept.joined(separator: " "), statedVolume(in: words))
    }

    /// The volume a title names of its own work, a title naming none being the first.
    private static func statedVolume(in words: [String]) -> Int {
        for (index, word) in words.enumerated() where volumeWords.contains(word) {
            guard index + 1 < words.count, let figure = Int(words[index + 1]) else { continue }

            return figure
        }

        return 1
    }

    /// The words of a title with "том 2", however it was bracketed or punctuated, taken out.
    private static func withoutVolume(_ words: [String]) -> [String] {
        var kept: [String] = []
        var index = 0

        while index < words.count {
            let next = index + 1 < words.count ? words[index + 1] : nil

            guard
                volumeWords.contains(words[index]),
                next?.allSatisfy(\.isNumber) == true
            else {
                kept.append(words[index])
                index += 1
                continue
            }

            index += 2
        }

        return kept
    }

    /// A title's words, lowercased, with the punctuation between them dropped.
    private static func pieces(of text: String) -> [String] {
        var letters: [Character] = []

        for scalar in text.lowercased().unicodeScalars {
            guard scalar.properties.generalCategory != .format else { continue }

            letters.append(CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " ")
        }

        return String(letters).split(separator: " ").map(String.init)
    }

    private static let volumeWords: Set<String> = [
        "том", "книга", "часть", "кн", "vol", "volume", "book", "part",
    ]
}
