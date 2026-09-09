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
        /// The title with the repeated wordRun removed. The whole title where removing it left nothing.
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

        let titles = books.map(\.title)
        let words = titles.map(Self.words)

        guard let wordRun = bestRun(in: words) else { return nil }

        let numbered = zip(books, words).map { book, words in
            let kept = wordRun.strip(words)

            return Numbered(book: book, number: wordRun.number(in: words), title: kept.isEmpty ? book.title : kept)
        }

        return Reading(books: numbered, missing: Self.missing(among: numbered.map(\.number)))
    }

    /// A title with the series' own name taken out of it, from either end.
    ///
    /// ``read(_:)`` does this properly, by finding the words several titles have in common. A series
    /// only half of whose titles carry the series name has no run to read, and the name is no more
    /// part of a book's own title for that: one library writes the series into a title where the other
    /// leaves it out, and the reader wants the book's name either way.
    ///
    /// Nothing is taken where nothing would be left. A book whose title is its series' name is called
    /// that, and an empty line on a shelf says less than a repeated one.
    public static func withoutSeries(_ title: String, in series: String?) -> String {
        guard let series else { return title }

        let kept = withoutLeadingName(withoutAside(title, in: series), in: series)

        return kept.isEmpty ? title : kept
    }

    /// "Name 3. Subtitle" and "Name. Subtitle": the words a series writes at the front of a title, and
    /// the figure they carry, are the series rather than the book.
    private static func withoutLeadingName(_ title: String, in series: String) -> String {
        var titleWords = words(in: title)
        let seriesWords = words(in: series).map(sameWordKey(of:))
        var taken = 0

        while taken < titleWords.count,
                taken < seriesWords.count,
                sameWordKey(of: titleWords[taken]) == seriesWords[taken] {
            taken += 1
        }

        guard taken > 0 else { return title }

        titleWords.removeFirst(taken)

        if isNumber(titleWords.first) { titleWords.removeFirst() }

        return titleWords.joined(separator: " ").trimmingCharacters(in: .whitespacesAndPunctuation)
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

        /// The figure inside the wordRun, or one where it carries none.
        func number(in words: [String]) -> Int {
            let wordRun: [String]

            switch anchor {
                case .front: wordRun = Array(words.prefix(count + (takesLooseNumber ? 1 : 0)))
                case .back: wordRun = Array(words.suffix(count))
            }

            return wordRun.compactMap(firstNumber).first ?? 1
        }
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
        words.count { title -> Bool in
            let runWords: [String] =
                switch wordRun.anchor {
                    case .front: Array(title.prefix(wordRun.count + (wordRun.takesLooseNumber ? 1 : 0)))
                    case .back: Array(title.suffix(wordRun.count))
                }

            return runWords.contains { firstNumber($0) != nil }
        }
    }

    private static func frontRun(in words: [[String]]) -> WordRun? {
        let count = commonCount(words) { $0 }

        guard count > 0 else { return nil }

        // "Name 3. Subtitle" and "Name. Subtitle" are the same series, one volume numbered and one not,
        // so the figure after the shared words belongs to the wordRun wherever it appears.
        let loose = words.contains { isNumber($0[safe: count]) }
        let wordRun = WordRun(anchor: .front, count: count, takesLooseNumber: loose)

        return numbered(words, by: wordRun) > 0 ? wordRun : nil
    }

    private static func backRun(in words: [[String]]) -> WordRun? {
        let count = commonCount(words) { $0.reversed() }

        guard count > 0 else { return nil }

        let wordRun = WordRun(anchor: .back, count: count, takesLooseNumber: false)

        return numbered(words, by: wordRun) > 0 ? wordRun : nil
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
