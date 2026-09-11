//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// Reads the volume numbers a series writes into its own book titles.
///
/// Publishers number a series in the titles themselves, and they do it two ways: at the front, as
/// "Name 3. Subtitle", or at the back, as "Subtitle (Name-3)". Either way the same words appear on
/// every book and only the figure moves, so the wordRun that repeats is the numbering and what is left is
/// the book's own name.
///
/// Nothing here guesses from one title. The pattern is whatever several titles have in common, which
/// is why a series of one is left alone.
public enum SeriesNumbering {
    /// One book, with the repeated words taken off its title and the figure they carried.
    public struct Numbered: Sendable, Identifiable {
        public let book: Book
        /// The volume this is, counting from one. A title carrying the words but no figure is the first.
        public let number: Int
        /// What the shelf calls the book: ``title(_:in:volume:)`` where it knows its series, and otherwise
        /// the title with the repeated run removed.
        public let title: String

        public var id: Int { book.id }
    }

    public struct Reading: Sendable {
        public let books: [Numbered]
        /// Volumes between the first and the last that no book on the shelf accounts for.
        public let missing: [Int]
    }

    /// Reads a series, or returns `nil` where its titles carry no numbering to read.
    public static func read(_ books: [Book]) -> Reading? {
        guard books.count > 1 else { return nil }

        // A dash standing between a name and its figure is no word of either.
        let words = books.map { Self.words(in: $0.title).filter { $0.contains { $0.isLetter || $0.isNumber } } }

        guard let wordRun = bestRun(in: words) else { return nil }

        // "Name 2: Subtitle" beside "Name: Subtitle" makes the name the numbering, colon or not.
        let numbersName = wordRun.anchor == .front && wordRun.takesLooseNumber

        let numbered = zip(books, words).map { book, words in
            let kept = wordRun.strip(words)
            // A book that knows its series is named by the rules for one; the run is for those that don't.
            let title =
                book.series == nil
                ? (kept.isEmpty ? book.title : kept)
                : Self.title(book.title, in: book.series, volume: book.seriesOrder, numbersItsName: numbersName)

            return Numbered(book: book, number: wordRun.number(in: words), title: title)
        }

        return Reading(books: numbered, missing: Self.missing(among: numbered.map(\.number)))
    }

    /// Each book's volume, keyed by book: what the book states first, as its file or the service gives it,
    /// and what its title says only for a book that states none. A book with neither is left out.
    ///
    /// - Parameter reading: the series read with ``read(_:)``, which is where the titles' figures come from.
    public static func volumes(of books: [Book], reading: Reading?) -> [Int: Int] {
        let titled = Dictionary(
            (reading?.books ?? []).map { ($0.book.id, $0.number) },
            uniquingKeysWith: { first, _ in first }
        )

        return books.reduce(into: [:]) { volumes, book in
            // A stated nought is absence written as a figure: a series counts from one.
            let stated = book.seriesOrder.flatMap { $0 > 0 ? $0 : nil }

            volumes[book.id] = stated ?? titled[book.id]
        }
    }

    /// What a series' shelf calls one of its books, given the volume its file states.
    ///
    ///     title("Ember 3. Tin Garden", in: "Ember", volume: 3)     // "Tin Garden"
    ///     title("Tin Garden. Book 2", in: "Ember", volume: 5)      // "Tin Garden /2"
    ///     title("Ember: Tin Garden", in: "Ember", volume: 1)       // "Ember: Tin Garden"
    ///     title("Ember (Ember-1)", in: "Ember", volume: 1)         // "Ember"
    ///
    /// - Parameter numbersItsName: true where the series' other titles number its name at the front,
    ///   as "Ember 2: Frost", so "Ember: Tin Garden" loses the name like its neighbours do.
    public static func title(
        _ title: String,
        in series: String?,
        volume: Int? = nil,
        numbersItsName: Bool = false
    ) -> String {
        guard let series else { return title }

        let unnumbered = withoutAside(withoutVolumeWord(title, volume: volume), in: series)
        let kept = withoutLeadingName(unnumbered, in: series, keepsNameBeforeColon: !numbersItsName)

        // A book whose title is its series' name and index is called by the name: an empty line says
        // less than a repeat.
        return kept.isEmpty ? leadingName(of: unnumbered, in: series) ?? unnumbered : kept
    }

    /// "Book 2" in a title goes where 2 is the book's own volume, and otherwise numbers a part as "/2".
    private static func withoutVolumeWord(_ title: String, volume: Int?) -> String {
        var titleWords = words(in: title)
        var index = 0
        var changed = false

        while index + 1 < titleWords.count {
            let word = titleWords[index]

            guard
                volumeWords.contains(word.lowercased().trimmingCharacters(in: .punctuationCharacters)),
                let (figure, tail) = figureAndTail(of: titleWords[index + 1])
            else {
                index += 1
                continue
            }

            // A bracket opened before the word closes after the figure, and goes with them.
            let rest = word.hasPrefix("(") ? tail.replacingOccurrences(of: ")", with: "") : tail

            if figure == volume {
                titleWords.removeSubrange(index ... index + 1)

                if index > 0, titleWords[index - 1].last?.isPunctuation == false { titleWords[index - 1] += rest }
            } else if index > 0 {
                titleWords[index - 1] = withoutStops(titleWords[index - 1])
                titleWords.replaceSubrange(index ... index + 1, with: [ "/\(figure)\(rest)" ])
                index += 1
            } else {
                index += 2
                continue
            }

            changed = true
        }

        return changed ? withoutStops(titleWords.joined(separator: " ")) : title
    }

    private static let volumeWords: Set<String> = [
        "том", "книга", "часть", "кн", "vol", "volume", "book", "part",
    ]

    /// A word that is a figure with nothing but punctuation after it, as in "4." or "2)".
    private static func figureAndTail(of word: String) -> (Int, String)? {
        let digits = word.prefix { $0.isNumber }
        let tail = word.dropFirst(digits.count)

        guard let figure = Int(digits), tail.allSatisfy(\.isPunctuation) else { return nil }

        return (figure, String(tail))
    }

    /// Text with the full stops, commas and colons trailing off its end taken away.
    private static func withoutStops(_ text: String) -> String {
        String(text.reversed().drop { ".,:;".contains($0) || $0.isWhitespace }.reversed())
    }

    /// "Name 3. Subtitle" and "Name. Subtitle": the words a series writes at the front of a title, and
    /// the figure they carry, are the series rather than the book. "Name: Subtitle" is the book's own.
    private static func withoutLeadingName(
        _ title: String,
        in series: String,
        keepsNameBeforeColon: Bool = true
    ) -> String {
        var titleWords = words(in: title)
        let taken = nameCount(in: titleWords, series: series)

        guard taken > 0, !(keepsNameBeforeColon && titleWords[taken - 1].hasSuffix(":")) else { return title }

        titleWords.removeFirst(taken)
        // "Name – 2. Subtitle": the dash between the name and its figure goes with them.
        titleWords = Array(titleWords.drop { $0.allSatisfy { $0.isPunctuation || $0.isSymbol } })

        if isNumber(titleWords.first) { titleWords.removeFirst() }

        return titleWords.joined(separator: " ").trimmingCharacters(in: .whitespacesAndPunctuation)
    }

    /// How many of a title's first words spell the series' name.
    private static func nameCount(in titleWords: [String], series: String) -> Int {
        let seriesWords = words(in: series).map(sameWordKey(of:))

        return zip(titleWords, seriesWords).prefix { sameWordKey(of: $0) == $1 }.count
    }

    /// The series' name as the title spells it at its front, where it does.
    private static func leadingName(of title: String, in series: String) -> String? {
        let titleWords = words(in: title)
        let taken = nameCount(in: titleWords, series: series)

        return taken > 0 ? withoutStops(titleWords.prefix(taken).joined(separator: " ")) : nil
    }

    /// A title with the series' own aside taken off the end of it.
    ///
    /// ``read(_:)`` takes the repeated words off wherever it can read a run across several titles. A
    /// series only half of whose titles carry the aside has no run to read, and the aside is no more
    /// part of a book's name for that: one library writes the series into a title where the other
    /// leaves it out, and the reader wants the book's name either way.
    ///
    /// Only the series' own aside goes. Anything else in brackets is part of what the book is called.
    private static func withoutAside(_ title: String, in series: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)

        guard trimmed.hasSuffix(")"), let opening = trimmed.lastIndex(of: "(") else { return title }

        let kept = String(trimmed[..<opening]).trimmingCharacters(in: .whitespaces)
        let aside = String(trimmed[trimmed.index(after: opening) ..< trimmed.index(before: trimmed.endIndex)])

        // A title that is nothing but its aside keeps it: there would be nothing left to call it.
        guard !kept.isEmpty, !names(in: series).isDisjoint(with: names(in: aside)) else { return title }

        return kept
    }

    /// The words in a name, with case, figures and punctuation off them. Short ones are dropped, since
    /// a preposition two series have in common is not the series.
    private static func names(in text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count > 2 })
    }

    // MARK: - Finding the wordRun

    /// Where the repeated words sit, and how many of them there are.
    private struct WordRun {
        let anchor: Anchor
        let count: Int
        /// True where the wordRun swallows a figure standing on its own, as in "Name 3. Subtitle".
        let takesLooseNumber: Bool
        /// Which of the covered words carry the volume. A figure every title shares, as in "99 Worlds", is
        /// part of the name.
        var figureSlots: Set<Int> = []

        enum Anchor { case front, back }

        func strip(_ words: [String]) -> String {
            var kept = words

            switch anchor {
                case .front:
                    let taken = min(count + (takesLooseNumber && isNumber(words[safe: count]) ? 1 : 0), kept.count)
                    kept.removeFirst(taken)
                case .back:
                    kept.removeLast(min(count, kept.count))
            }

            return kept.joined(separator: " ").trimmingCharacters(in: .whitespacesAndPunctuation)
        }

        /// One title's words the run covers, counted from the end it is anchored to.
        func covered(_ words: [String]) -> [String] {
            switch anchor {
                case .front: Array(words.prefix(count + (takesLooseNumber ? 1 : 0)))
                case .back: Array(words.suffix(count).reversed())
            }
        }

        /// The volume figure in one title, where it carries one.
        func figure(in words: [String]) -> Int? {
            covered(words).enumerated().lazy.compactMap { slot, word in
                figureSlots.contains(slot) ? firstNumber(word) : nil
            }.first
        }

        /// The volume one title states, or one where it carries no figure.
        func number(in words: [String]) -> Int { figure(in: words) ?? 1 }
    }

    private static func bestRun(in words: [[String]]) -> WordRun? {
        let candidates = [ frontRun(in: words), backRun(in: words) ].compactMap { $0 }

        // The wordRun that numbers the most books wins; a longer wordRun breaks a tie, since more words in
        // common is stronger evidence that they are the series and not the book.
        return candidates.max { left, right in
            (numbered(words, by: left), left.count) < (numbered(words, by: right), right.count)
        }
    }

    /// How many titles the wordRun actually finds a figure in. A wordRun nobody numbers is not a numbering.
    private static func numbered(_ words: [[String]], by wordRun: WordRun) -> Int {
        words.count { wordRun.figure(in: $0) != nil }
    }

    /// The run with the places its figures differ from title to title, which are the ones numbering it.
    private static func withFigures(_ run: WordRun, in words: [[String]]) -> WordRun? {
        let covered = words.map(run.covered)
        let width = covered.map(\.count).max() ?? 0
        var counted = run

        counted.figureSlots = Set((0 ..< width).filter { slot in
            Set(covered.map { $0[safe: slot].flatMap(firstNumber) }).count > 1
        })

        return numbered(words, by: counted) > 0 ? counted : nil
    }

    private static func frontRun(in words: [[String]]) -> WordRun? {
        let count = commonCount(words) { $0 }

        guard count > 0 else { return nil }

        // "Name 3. Subtitle" and "Name. Subtitle" are the same series, one volume numbered and one not,
        // so the figure after the shared words belongs to the wordRun wherever it appears.
        let loose = words.contains { isNumber($0[safe: count]) }

        return withFigures(WordRun(anchor: .front, count: count, takesLooseNumber: loose), in: words)
    }

    private static func backRun(in words: [[String]]) -> WordRun? {
        let count = commonCount(words) { $0.reversed() }

        guard count > 0 else { return nil }

        return withFigures(WordRun(anchor: .back, count: count, takesLooseNumber: false), in: words)
    }

    /// How many words every title shares, read in whichever direction `order` gives.
    private static func commonCount(_ words: [[String]], _ order: ([String]) -> [String]) -> Int {
        let ordered = words.map(order)

        guard let shortest = ordered.map(\.count).min() else { return 0 }

        var count = 0

        while count < shortest, let first = ordered.first?[count] {
            guard ordered.allSatisfy({ sameWordKey(of: $0[count]) == sameWordKey(of: first) }) else { break }

            count += 1
        }

        return count
    }

    // MARK: - Words and figures

    private static func words(in title: String) -> [String] {
        title.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// What makes two words the same word: their case, the figures in them and the punctuation hung
    /// off their ends are all beside the point. "Name," "name" and "Name-3" all read as the same word
    /// as "Name-7".
    private static func sameWordKey(of word: String) -> String {
        var key = ""

        for character in word.lowercased() where !character.isPunctuation && !character.isSymbol {
            key.append(character.isNumber ? "#" : character)
        }

        // A wordRun of figures is one figure however many digits it has.
        return key.replacingOccurrences(of: "#+", with: "#", options: .regularExpression)
    }

    private static func isNumber(_ word: String?) -> Bool {
        guard let word else { return false }

        return firstNumber(word) != nil && !word.contains { $0.isLetter }
    }

    private static func firstNumber(_ word: String) -> Int? {
        let digits = word.drop { !$0.isNumber }.prefix { $0.isNumber }

        return digits.isEmpty ? nil : Int(digits)
    }

    /// Every volume between the first and the last that nothing on the shelf accounts for.
    private static func missing(among numbers: [Int]) -> [Int] {
        let held = Set(numbers)

        guard let last = held.max(), let first = held.min(), last > first else { return [] }

        return (first ... last).filter { !held.contains($0) }
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension CharacterSet {
    fileprivate static let whitespacesAndPunctuation = CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters)
}
