//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import AuthorTodayBooks
import BookKit
import BookRenderer
import BookStorage
import Foundation

extension LibraryScreen {
    @Observable @MainActor
    final class Model {
        /// One heading of the list: a series, or a single book that belongs to none. A series can carry
        /// more than one author, so the authors are left to the rows.
        struct Group: Identifiable {
            let id: String
            let series: String?
            let works: [Book]
            /// The last time any book here gained anything, which is what orders the list.
            let updated: Date
            /// True where the reader put this series together themselves.
            var isCustom = false
            /// The volume numbers the titles carry, where they carry any. Absent for a series whose
            /// books are named without a numbering, and for a book standing on its own.
            var numbering: SeriesNumbering.Reading?

            /// What a book is called on this card, with the series' own aside off the end of it.
            private func named(_ work: Book) -> String {
                SeriesNumbering.withoutSeries(work.title, in: series)
            }

            /// Who the series is by: the name most of its books carry.
            ///
            /// They don't all have to agree. A co-author joins a long series partway through, and two
            /// copies of one book can spell a name the other way round, so a heading that went blank at
            /// the first difference would be blank for most series on a shelf.
            var author: String? {
                let names = works.map(\.authorLine).filter { !$0.isEmpty }
                var counted: [String: Int] = [:]

                for name in names { counted[name, default: 0] += 1 }

                let most = counted.values.max()

                // A tie goes to the book the card leads with, which is the one being read.
                return names.first { counted[$0] == most }
            }

            /// The rows to draw, in order: the books held, and the volumes nothing accounts for.
            var rows: [SeriesRow] {
                // A number the file states beats one read off a title. The publisher wrote the first;
                // the second is inference, however good, and inference is what gets a volume wrong.
                if let stated { return stated }

                guard
                    let numbering
                else {
                    // A series whose titles carry no numbering is still numbered, counting from one at
                    // the bottom, which is where a series starts. A book on its own is not a series.
                    guard
                        series != nil,
                        works.count > 1
                    else {
                        return works.map { .book($0, number: nil, title: named($0)) }
                    }

                    return works.enumerated().map { index, work in
                        .book(work, number: works.count - index, title: named(work))
                    }
                }

                let held = numbering.books.map { SeriesRow.book($0.book, number: $0.number, title: $0.title) }

                guard !numbering.missing.isEmpty else { return held }

                // A gap sits where its volume would have, which is what makes it read as a gap rather
                // than as a note at the end of the list.
                let missing = numbering.missing.map(SeriesRow.missing)
                let order = numbering.books.map(\.number)
                let descending = order.count > 1 && (order.first ?? 0) > (order.last ?? 0)

                return (held + missing).sorted { left, right in
                    descending ? left.number > right.number : left.number < right.number
                }
            }

            /// A series whose books each state their own place, as rows.
            ///
            /// Nothing where any book is silent about it, or where two claim the same volume: a series
            /// half-numbered by its files is worse than one numbered from its titles throughout.
            private var stated: [SeriesRow]? {
                // A series the reader assembled states nothing about volumes. What is filed for it is
                // each book's place in the list they arranged, which is a position rather than a
                // volume, so the card numbers it from the bottom like any series whose books carry no
                // number of their own.
                guard !isCustom, series != nil, works.count > 1 else { return nil }

                // A volume is counted from one, so nought is absence written as a figure rather than a
                // place in the series. Taken as one, it draws a book nought and moves every volume
                // after it down by one.
                let numbers = works.compactMap(\.seriesOrder).filter { $0 > 0 }

                guard numbers.count == works.count, Set(numbers).count == numbers.count else { return nil }

                // The titles still come from the numbering, which is what takes the series' own repeated
                // words off them. Only the figure is the file's.
                let shortened = numbering?.books.reduce(into: [Int: String]()) { $0[$1.book.id] = $1.title } ?? [:]
                let held = works.map { work in
                    SeriesRow.book(work, number: work.seriesOrder, title: shortened[work.id] ?? named(work))
                }

                guard let first = numbers.min(), let last = numbers.max(), last > first else { return held }

                let gaps = (first ... last).filter { !numbers.contains($0) }

                guard !gaps.isEmpty else { return held }

                let descending = (numbers.first ?? 0) > (numbers.last ?? 0)

                return (held + gaps.map(SeriesRow.missing)).sorted { left, right in
                    descending ? left.number > right.number : left.number < right.number
                }
            }
        }

        /// A line in a series card: a book on the shelf, or a volume between two that is not.
        enum SeriesRow: Identifiable {
            case book(Book, number: Int?, title: String)
            case missing(Int)

            var id: String {
                switch self {
                    case let .book(work, _, _): "book:\(work.id)"
                    case let .missing(number): "gap:\(number)"
                }
            }

            var number: Int {
                switch self {
                    case let .book(_, number, _): number ?? 0
                    case let .missing(number): number
                }
            }
        }

        /// What the list is showing. The service's shelves say nothing dependable about where a reader
        /// has got to, so the app decides this from what has been written and what has been read.
        enum Filter: String, CaseIterable, Identifiable {
            /// The author is still writing it, or there is text left to read. Both mean "open me".
            case reading
            /// Written to its end and read to its end.
            case finished
            case everything

            var id: String { rawValue }

            var title: String {
                switch self {
                    case .reading: String(localized: "Reading")
                    case .finished: String(localized: "Finished")
                    case .everything: String(localized: "All books")
                }
            }

            var systemImage: String {
                switch self {
                    case .reading: "book"
                    case .finished: "checkmark.circle"
                    case .everything: "books.vertical"
                }
            }

            func includes(_ work: Book) -> Bool {
                switch self {
                    case .reading: !work.isFinishedReading
                    case .finished: work.isFinishedReading
                    case .everything: true
                }
            }

            /// Whether a card belongs under this filter.
            ///
            /// A series is one thing on the shelf, so it is kept or hidden whole. One with anything
            /// left in it is still being read, books already finished included: those are what the
            /// reader is reading through, and a series that showed only its unread half would hide
            /// where the reader had got to. Only a series read to its last book is finished.
            func includes(_ works: [Book]) -> Bool {
                switch self {
                    case .reading: works.contains { !$0.isFinishedReading }
                    case .finished: !works.isEmpty && works.allSatisfy(\.isFinishedReading)
                    case .everything: true
                }
            }
        }

        var filter: Filter = .reading
        var searchText = ""

        /// True while the shelf is picking books out rather than opening them.
        var isSelecting = false {
            didSet {
                if !isSelecting { selection = [] }
            }
        }

        var selection: Set<Int> = []

        /// The names of the series the reader put together, which are kept in the order they chose
        /// rather than newest first.
        private(set) var madeSeries: Set<String> = []

        private(set) var works: [Book] = []
        private(set) var isLoading = false
        private(set) var errorMessage: String?
        private(set) var hasLoaded = false

        /// True while the list is the stored one and the service could not be reached.
        private(set) var isOffline = false

        /// True while a picked file is being read into the library.
        var isImporting: Bool { BookInbox.shared.isImporting }

        /// How far each book still being prepared has got, so the shelf can say so.
        private(set) var processing: [Int: BookProcessor.Progress] = [:]

        @ObservationIgnored
        private let session: SessionStore

        @ObservationIgnored
        private let store: SQLiteBookStore

        init(session: SessionStore, store: SQLiteBookStore = .shared) {
            self.session = session
            self.store = store
        }

        /// Every book on screen, the ones a kept series carries along with it included.
        var visibleWorks: [Book] { groups.flatMap(\.works) }

        /// The shelf's own books: one copy of each, whichever of them is the better one to hold.
        var library: [Book] { Self.oneOfEach(works, sameText: sameText, arranged: madeSeries) }

        /// Every local book's own text, hashed, so two copies of one book are one book on the shelf.
        private(set) var sameText: [Int: String] = [:]

        /// The books the local title and author search leaves, before the filter has had its say.
        private var searchedWorks: [Book] {
            guard let query else { return library }

            return library.filter {
                $0.title.lowercased().contains(query) || $0.authorLine.lowercased().contains(query)
            }
        }

        /// What is being looked for, where anything is.
        private var query: String? {
            let asked = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            return asked.isEmpty ? nil : asked
        }

        /// A search stands the filter aside: a reader looking for a book by name is looking for it
        /// wherever it is, and a shelf answering "nothing found" because the book was finished would
        /// be wrong rather than filtered.
        private var searchFilter: Filter { query == nil ? filter : .everything }

        /// Books in a series stand together under its name, latest first; a book in no series stands
        /// alone. Whatever was last read or last gained a chapter comes first.
        /// The filter runs over whole cards rather than over books, so a series the reader is partway
        /// through arrives entire, and the books behind them stay where they were.
        var groups: [Group] {
            let searched = searchedWorks
            let named = Dictionary(grouping: searched.filter { $0.series != nil }) { $0.series ?? "" }
            // One book is not a series, whatever the book says it belongs to. A card built round a
            // single row claims the shelf holds a run of them, and the row already names the series it
            // came from without pretending to hold it.
            let series = named.filter { $0.value.count > 1 }
            let lonely = named.filter { $0.value.count == 1 }.values.flatMap { $0 }

            let grouped = series.compactMap { title, works -> Group? in
                guard searchFilter.includes(works) else { return nil }

                // A series the reader assembled keeps the order they put it in; one the service named
                // leads with its newest book, which is the one still gaining chapters.
                let made = madeSeries.contains(title)

                let ordered = Self.ordered(works, arrangedByHand: made)

                return Group(
                    id: "series:\(title)",
                    series: title,
                    works: ordered,
                    updated: works.map(Self.updated).max() ?? .distantPast,
                    isCustom: made,
                    // Read for every series, the reader's own included. What they arranged is the
                    // order, and reading the titles takes nothing from that: it gives the volumes
                    // their real numbers and is the only thing that can say which of them is absent.
                    numbering: SeriesNumbering.read(ordered)
                )
            }
            let alone = (searched.filter { $0.series == nil } + lonely)
                .filter { searchFilter.includes([ $0 ]) }
                .map { work in
                    Group(id: "work:\(work.id)", series: nil, works: [ work ], updated: Self.updated(work))
                }

            return (grouped + alone).sorted(by: Self.byUpdate)
        }

        /// When the service last changed the book. Reading it is not a change to it, so the list holds
        /// still while the reader reads rather than shuffling under them.
        private static func updated(_ work: Book) -> Date { work.lastUpdateTime ?? .distantPast }

        /// The order a series' books stand in, wherever they are shown. A series the reader arranged
        /// keeps the order they put it in; one the service named leads with its newest book.
        static func ordered(_ works: [Book], arrangedByHand: Bool) -> [Book] {
            works.sorted(by: arrangedByHand ? byChosenOrder : withinSeries)
        }

        /// Latest book in the series first, which is the one with a chapter still arriving. Titles
        /// compare numerically, so a series the service gives no order for still lands newest first.
        private static func withinSeries(_ left: Book, _ right: Book) -> Bool {
            guard
                left.seriesOrder == right.seriesOrder
            else {
                return (left.seriesOrder ?? .min) > (right.seriesOrder ?? .min)
            }

            return left.title.localizedStandardCompare(right.title) == .orderedDescending
        }

        /// The order the reader put the series in, first book first.
        private static func byChosenOrder(_ left: Book, _ right: Book) -> Bool {
            (left.seriesOrder ?? 0) < (right.seriesOrder ?? 0)
        }

        /// Newest first, and books the service gives no date for keep a fixed order of their own rather
        /// than whatever the grouping happened to produce.
        private static func byUpdate(_ left: Group, _ right: Group) -> Bool {
            guard
                left.updated == right.updated
            else {
                return left.updated > right.updated
            }

            return left.id.localizedStandardCompare(right.id) == .orderedAscending
        }

        /// Books this filter has something to say about, which is not the same as rows it opens: a
        /// series kept for one unread book brings the rest of itself with it. The number that helps is
        /// how much is left to read, not how much is on screen.
        func count(for filter: Filter) -> Int? {
            guard !works.isEmpty else { return nil }

            return library.count(where: filter.includes)
        }

        // MARK: - The same book, held twice

        /// One copy of each book, where the reader owns some of them in both libraries.
        ///
        /// A book bought on one service and owned on the other is one book on the shelf. Which copy is
        /// shown is decided per book rather than once for the whole library, because the right answer
        /// changes with where the reader has got to.
        static func oneOfEach(
            _ works: [Book],
            sameText: [Int: String] = [:],
            arranged: Set<String> = []
        ) -> [Book] {
            byTitle(sameBooks(works, sameText: sameText), arranged: arranged)
        }

        /// Copies whose text is the very same text, folded into one.
        ///
        /// A book carried in by hand and the same book brought across from a service are two files
        /// with one text between them, and no comparing of titles is needed to say so: they hash
        /// alike. This runs first, since a book itself says more than what it was named.
        private static func sameBooks(_ works: [Book], sameText: [Int: String]) -> [Book] {
            var chosen: [String: Book] = [:]
            var order: [String] = []

            for work in works {
                // A book with no text on the device stands for itself: the service holds it, and two
                // of those are told apart by name like everything else.
                let key = sameText[work.id].map { "text:\($0)" } ?? "work:\(work.id)"

                guard
                    let rival = chosen[key]
                else {
                    chosen[key] = work
                    order.append(key)
                    continue
                }

                chosen[key] = titled(furtherRead(rival, over: work), from: rival, and: work)
            }

            return order.compactMap { chosen[$0] }
        }

        /// Of two copies of one text, the one the reader has got further into. Nothing else tells them
        /// apart: the words are identical, so what is worth keeping is the place in them.
        private static func furtherRead(_ left: Book, over right: Book) -> Book {
            (right.readingProgress ?? 0) > (left.readingProgress ?? 0) ? right : left
        }

        private static func byTitle(_ works: [Book], arranged: Set<String>) -> [Book] {
            var chosen: [String: Book] = [:]
            var order: [String] = []

            for work in works {
                var name = title(of: work)

                // Alike in name but not the same book. Keyed away under this copy's own id rather than
                // dropped, so a third copy still meets whichever of the two it belongs with.
                if let rival = chosen[name], !isTheSameBook(rival, work, arranged: arranged) {
                    name += "#\(work.id)"
                }

                guard
                    let rival = chosen[name]
                else {
                    chosen[name] = work
                    order.append(name)
                    continue
                }

                chosen[name] = titled(preferred(rival, over: work), from: rival, and: work)
            }

            return order.compactMap { chosen[$0] }
        }

        /// Which of two copies of one book the shelf holds: the one whose text is on the device.
        ///
        /// A copy the reader owns as a file opens with no network and cannot be withdrawn, so where
        /// the device holds the words there is nothing the service's copy is needed for. Each copy
        /// keeps its own reading position, since a position is kept against a book rather than against
        /// a title: a book read under the service's copy and shown as the file opens where the file
        /// was last left.
        private static func preferred(_ left: Book, over right: Book) -> Book {
            let leftIsFile = BookNumbering.isLocal(left.id)

            // Two of a kind. Nothing to choose between them, so the one already held stands.
            guard leftIsFile != BookNumbering.isLocal(right.id) else { return left }

            return leftIsFile ? left : right
        }

        /// The copy that is kept, wearing the fuller of the two titles.
        ///
        /// One library writes the series and its volume into a title where the other leaves them out,
        /// and which copy is kept turns on where its words are rather than on what it is called. The
        /// numbering is whatever every title has in common, so a series whose titles half state their
        /// volume states it nowhere, and the shelf falls back to counting rows.
        private static func titled(_ chosen: Book, from left: Book, and right: Book) -> Book {
            let other = chosen.id == left.id ? right : left

            guard aside(of: chosen.title) == nil, aside(of: other.title) != nil else { return chosen }

            return chosen.titled(other.title)
        }

        /// Whether two copies alike in name are one book.
        private static func isTheSameBook(_ left: Book, _ right: Book, arranged: Set<String>) -> Bool {
            sameAuthor(left, right) && !areDifferentVolumes(left, right, arranged: arranged)
        }

        /// Whether two copies name the same author.
        ///
        /// Two libraries spell one name several ways: with a patronymic and without, family name first
        /// and last, and with a co-author on the volumes they wrote together. Comparing the strings
        /// keeps copies of one book apart, so what is compared is the names they have in common.
        ///
        /// One name in common settles it only where one of the two is a single name. Otherwise a
        /// shared given name is not evidence, and two names are.
        private static func sameAuthor(_ left: Book, _ right: Book) -> Bool {
            let mine = Set(plain(left.authorLine).split(separator: " "))
            let theirs = Set(plain(right.authorLine).split(separator: " "))

            guard !mine.isEmpty, !theirs.isEmpty else { return true }

            return mine.intersection(theirs).count >= min(2, min(mine.count, theirs.count))
        }

        /// Two copies that each state a volume, and state different ones, are two books.
        ///
        /// Only where their titles carry different asides as well. One library writes the series into
        /// a title and the other leaves it out, so a copy carrying the aside and a copy without it are
        /// one book whatever figures they state. What the aside tells apart is two volumes that share
        /// a base title, where the aside is the only thing that ever differed.
        private static func areDifferentVolumes(_ left: Book, _ right: Book, arranged: Set<String>) -> Bool {
            guard
                let mine = volume(of: left, arranged: arranged),
                let theirs = volume(of: right, arranged: arranged),
                mine != theirs,
                let myAside = aside(of: left.title),
                let theirAside = aside(of: right.title)
            else { return false }

            return plain(myAside) != plain(theirAside)
        }

        /// The aside at the end of a title, where it has one worth reading.
        private static func aside(of title: String) -> String? {
            let trimmed = title.trimmingCharacters(in: .whitespaces)

            guard
                trimmed.hasSuffix(")"),
                let opening = trimmed.lastIndex(of: "("),
                !trimmed[..<opening].trimmingCharacters(in: .whitespaces).isEmpty
            else { return nil }

            return String(trimmed[trimmed.index(after: opening) ..< trimmed.index(before: trimmed.endIndex)])
        }

        /// The volume a book states, which is nothing at all inside a series the reader assembled.
        ///
        /// What is filed for one of those is each book's place in the list they arranged, and two
        /// copies of one book are given two places. Read as volumes, those places say the copies are
        /// different books, which is exactly the pair that most needs joining.
        private static func volume(of work: Book, arranged: Set<String>) -> Int? {
            guard let series = work.series, arranged.contains(series) else { return work.seriesOrder }

            return nil
        }

        /// What two copies of one book are looked up under: the title alone, with the series aside,
        /// case, punctuation and the odd stray mark taken out of it.
        ///
        /// The author is left out of the key and compared afterwards, because the two libraries rarely
        /// spell a name the same way and a key they disagree on never brings the copies together to be
        /// compared at all.
        private static func title(of work: Book) -> String {
            plain(withoutAside(work.title))
        }

        /// A title with the aside at the end of it taken off.
        ///
        /// One library writes the series into the name where the other leaves it out, so a book and
        /// the same book followed by its series in brackets are one book under two spellings. What
        /// that aside sometimes carries instead is the volume, which is why a stated volume is looked
        /// at before two books alike in name are treated as one.
        private static func withoutAside(_ title: String) -> String {
            let trimmed = title.trimmingCharacters(in: .whitespaces)

            guard trimmed.hasSuffix(")"), let opening = trimmed.lastIndex(of: "(") else { return title }

            let kept = trimmed[..<opening].trimmingCharacters(in: .whitespaces)

            // A title that is nothing but its aside keeps it: there would be nothing left to match on.
            return kept.isEmpty ? title : kept
        }

        private static func plain(_ text: String) -> String {
            var letters: [Character] = []

            for scalar in text.lowercased().unicodeScalars {
                guard scalar.properties.generalCategory != .format else { continue }

                letters.append(CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " ")
            }

            return withoutVolumeWords(String(letters).split(separator: " ").map(String.init))
                .joined(separator: " ")
        }

        /// One library writes a volume as "Том 2" where the other writes it as "-2", so the word is
        /// dropped and the figure kept. Only where a figure follows it: a book with a person called
        /// Tom in its title is not stating a volume.
        private static func withoutVolumeWords(_ words: [String]) -> [String] {
            words.enumerated().compactMap { index, word in
                let next = index + 1 < words.count ? words[index + 1] : nil
                let statesAVolume = Self.volumeWords.contains(word) && next?.allSatisfy(\.isNumber) == true

                return statesAVolume ? nil : word
            }
        }

        private static let volumeWords: Set<String> = [
            "том", "часть", "книга", "кн", "vol", "volume", "book", "part",
        ]

        /// Mirrored out of user defaults, which nothing observes, so the badges redraw when a sweep
        /// finds something.
        private(set) var newChaptersByWork: [Int: Int] = UpdateBadge.newChaptersByWork

        func newChapters(for workId: Int) -> Int { newChaptersByWork[workId] ?? 0 }

        func dismissError() { errorMessage = nil }

        // MARK: - Runs the reader has read through

        /// The series showing every book as a cover.
        ///
        /// A card opens on what is left to read: a series read to its end is a wall of artwork saying
        /// nothing the reader wants, and its spines say the same thing in a tenth of the room.
        private(set) var openCovers: Set<String> = []

        func showsEveryCover(_ series: String) -> Bool { openCovers.contains(series) }

        func toggleCovers(of series: String) {
            if openCovers.contains(series) {
                openCovers.remove(series)
            } else {
                openCovers.insert(series)
            }
        }

        /// True where the reader is done with this book and nothing new has arrived in it.
        ///
        /// Read to the end of a book still being written doesn't count: the next chapter is what the
        /// reader is waiting for, and a folded row is the wrong place to be told it landed.
        func isBehindTheReader(_ work: Book) -> Bool {
            work.isFinishedReading && newChapters(for: work.id) == 0
        }

        /// A series as the places on its own shelf: a book the reader holds, or a volume they don't.
        func slots(of group: Group) -> [SeriesSlot] {
            group.rows.map { row in
                switch row {
                    case let .book(work, number, title):
                        .book(work, number: number, title: title, isRead: isBehindTheReader(work))
                    case let .missing(number):
                        .missing(number)
                }
            }
        }

        // MARK: - Series the reader puts together

        /// Files the books picked out as one series, in the order they were listed.
        ///
        /// A series already selected brings its books with it, so combining two series and a loose book
        /// gives one series of everything rather than a series holding a series.
        func combineSelection(named series: String) async {
            let name = series.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !name.isEmpty, selection.count > 1 else { return }

            await store.store(series: name, workIds: ordered(selection))
            isSelecting = false
            await refreshFromStore()
        }

        /// The picked books in the order the shelf is showing them, so combining keeps what the reader
        /// can see rather than the order a set happens to iterate in.
        private func ordered(_ ids: Set<Int>) -> [Int] {
            groups.flatMap(\.works).map(\.id).filter(ids.contains)
        }

        func reorder(series: String, workIds: [Int]) async {
            await store.store(series: series, workIds: workIds)
            await refreshFromStore()
        }

        /// Gives a series back to whatever the service and the files say, and takes the name off it.
        func ungroup(series: String) async {
            let ids = works.filter { $0.series == series }.map(\.id)

            await store.removeFromCustomSeries(workIds: ids)
            await refreshFromStore()
        }

        func toggle(_ work: Book) {
            if selection.contains(work.id) {
                selection.remove(work.id)
            } else {
                selection.insert(work.id)
            }
        }

        /// Picking a series picks every book in it, since a series is what the shelf shows as one thing.
        func toggle(group: Group) {
            let ids = Set(group.works.map(\.id))

            if ids.isSubset(of: selection) {
                selection.subtract(ids)
            } else {
                selection.formUnion(ids)
            }
        }

        // MARK: - Books from files

        /// Reads a picked file into the library and starts preparing it.
        ///
        /// The book is on the shelf and readable the moment its text is stored. Putting it through the
        /// typesetter happens behind that, so a long book doesn't hold the picker open.
        func importBook(from url: URL) async {
            guard
                let work = await BookInbox.shared.accept(url)
            else {
                errorMessage = BookInbox.shared.errorMessage
                return
            }

            await adoptImported(workId: work.id)
        }

        /// Draws a newly arrived book on the shelf and follows it while it is prepared. Also the way a
        /// book opened from another app reaches the list.
        func adoptImported(workId: Int) async {
            await refreshFromStore()
            watch(workId: workId)
        }

        /// Follows one book's preparation until it finishes, so the shelf can show a bar against it.
        private func watch(workId: Int) {
            Task { [weak self] in
                while !Task.isCancelled {
                    guard let progress = await BookProcessor.shared.progress(of: workId) else { return }

                    self?.processing[workId] = progress.isComplete ? nil : progress

                    if progress.isComplete { return }

                    try? await Task.sleep(for: .milliseconds(400))
                }
            }
        }

        /// Takes an imported book off the device outright. Its text is here and nowhere else.
        func deleteLocalBook(_ work: Book) async {
            guard BookNumbering.isLocal(work.id) else { return }

            works.removeAll { $0.id == work.id }
            processing[work.id] = nil
            await BookProcessor.shared.stop(workId: work.id)
            await BookInstaller.remove(workId: work.id)
        }

        /// True for a book that came from a file rather than the service.
        func isLocal(_ work: Book) -> Bool { BookNumbering.isLocal(work.id) }

        func loadIfNeeded() async {
            guard !hasLoaded else { return }

            madeSeries = Set(await store.customSeries().values.map(\.series))
            await showStoredLibrary()
            await reload()
            await adoptServerPositions()
        }

        /// Redraws the list from the store, without asking the service anything.
        ///
        /// Reading fills the rings, and the service knows nothing about it: the position and the
        /// progress it implies live here alone. Coming back from a book has to read them again.
        func refreshFromStore() async {
            let stored = await store.books()

            await readTextHashes()
            // Which series the reader put together, read back with everything else: filing one is
            // what decides whether a card is theirs to order, and it can be filed from the series'
            // own screen while the shelf stands behind it.
            madeSeries = Set(await store.customSeries().values.map(\.series))

            guard !stored.isEmpty else { return }

            apply(entries: stored)
            newChaptersByWork = UpdateBadge.newChaptersByWork
            // Reading a book to its end drops it from the badge, and nothing else would notice.
            await UpdateBadge.refresh()
        }

        /// Adopts the positions the service holds where they are newer than this device's own.
        ///
        /// The service records nothing this app sends, but it does record what its own site does, so a
        /// book read on author.today opens here where it was left. Progress comes back as a percentage
        /// of the chapter, which the chapter's own length turns into the offset the reader works in.
        private func adoptServerPositions() async {
            guard session.isSignedIn else { return }
            guard
                let entries = try? await session.client.readingProgress(
                    since: .now.addingTimeInterval(-Self.positionWindow)
                )
            else { return }

            for entry in entries {
                guard let chapterId = entry.chapterId, let readAt = entry.lastReadTime else { continue }

                let mine = await store.position(workId: entry.workId)

                guard (mine?.updatedAt ?? .distantPast) < readAt else { continue }

                let length =
                    await store.chapters(workId: entry.workId)
                    .first { $0.id == chapterId }?
                    .textLength ?? 0

                await store.store(position: .init(
                    workId: entry.workId,
                    chapterId: chapterId,
                    characterOffset: Int((entry.chapterProgress ?? 0) / 100 * Double(length)),
                    updatedAt: readAt
                ))
            }
        }

        /// How far back to ask for positions. The service answers with everything touched since.
        private static let positionWindow: TimeInterval = 90 * 24 * 60 * 60

        /// Draws the library the device already has before the service is asked anything, so it opens
        /// instantly and opens at all with no network.
        private func showStoredLibrary() async {
            let stored = await store.books()

            await readTextHashes()

            guard !stored.isEmpty, works.isEmpty else { return }

            apply(entries: stored)
        }

        /// What each local book's text hashes to, which is what says two rows are one book.
        private func readTextHashes() async {
            let held = await store.localBooks()
            let hashes = held.reduce(into: [Int: String]()) { found, record in
                guard let hash = record.contentHash else { return }

                found[record.workId] = hash
            }

            if sameText != hashes { sameText = hashes }
        }

        /// Looks for chapters published since the device last looked.
        ///
        /// The shelf carries no chapters, so reloading it cannot answer "is there anything new to
        /// read?" on its own. What it does carry is each book's update time, and a book whose time has
        /// moved is the only one worth asking for a table of contents. Once a day everything is walked
        /// instead, which is also what fills the offline cache.
        private func findNewChapters(since previous: [Book], in entries: [Book]) async {
            let lastChecked = UpdateBadge.lastCheckedAt
            let isDue = lastChecked.map { Date.now.timeIntervalSince($0) > BackgroundRefresh.interval } ?? true
            let books = isDue ? entries : Self.changed(from: previous, to: entries)

            guard !books.isEmpty else { return }

            _ = await ChapterUpdateService(client: session.client).sweep(
                works: books,
                // A partial pass is for the badge alone; downloading bodies is the daily pass's job.
                chapterBudget: isDue ? ChapterUpdateService.foregroundChapterBudget : 0,
                isComplete: isDue
            )
            newChaptersByWork = UpdateBadge.newChaptersByWork
            // Storing a table of contents re-derives that book's progress, so the rings are read back.
            await refreshFromStore()
        }

        /// The books the service has touched since this device last saw them, plus the ones it has
        /// never seen.
        private static func changed(from previous: [Book], to entries: [Book]) -> [Book] {
            let before = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            return entries.filter { before[$0.id]?.lastUpdateTime != $0.lastUpdateTime }
        }

        /// One sweep at a time; a second pull while one is walking would only ask the same questions.
        @ObservationIgnored
        private var sweepTask: Task<Void, Never>?

        /// The walk runs behind the list rather than under the refresh spinner: it is one request per
        /// changed book, and the shelf is already on screen.
        private func startSweep(since previous: [Book], in entries: [Book]) {
            guard sweepTask == nil else { return }

            sweepTask = Task { [weak self] in
                await self?.findNewChapters(since: previous, in: entries)
                self?.sweepTask = nil
            }
        }

        func reload() async {
            guard !isLoading else { return }

            isLoading = true
            errorMessage = nil

            defer { isLoading = false }

            do {
                let previous = works
                let library = try await session.client.fullUserLibrary()
                let entries = library.worksInLibrary.map(Book.init)
                await store.replaceLibrary(with: entries)
                // Read back rather than painting what arrived: the service carries no progress this
                // device made, so its copy would undo a book marked read the moment it landed.
                let merged = await store.books()

                await readTextHashes()
                apply(entries: merged.isEmpty ? entries : merged)
                isOffline = false
                hasLoaded = true
                startSweep(since: previous, in: entries)
            } catch let error as AuthorTodayError where error.requiresReauthentication {
                errorMessage = error.localizedDescription
            } catch {
                // The stored library is already on screen; say the list is stale rather than replacing
                // it with an error.
                isOffline = true

                if works.isEmpty { errorMessage = String(localized: "Couldn’t load your library.") }
            }
        }

        /// Marks a book read through: the ring fills, and the book page's chapter marks fill with it,
        /// which means putting the position at the end of the last chapter it has.
        func markAsRead(_ work: Book) async {
            if let index = works.firstIndex(where: { $0.id == work.id }) {
                works[index].readingProgress = 1
            }

            await store.store(progress: 1, workId: work.id)

            // The service keeps no progress, but it does keep a shelf, and Finished is its way of
            // saying the reader is done with a book.
            if !isLocal(work) {
                try? await session.client.updateLibraryState(workIds: [ work.id ], state: .finished)
            }

            if let index = works.firstIndex(where: { $0.id == work.id }) {
                works[index].libraryState = .finished
                await store.store(book: works[index])
            }

            guard let last = await contents(of: work.id).last(where: \.isReadable) else { return }

            let isLocalBook = isLocal(work)

            await store.store(position: .init(
                workId: work.id,
                chapterId: last.id,
                // Past the end when the chapter's length is unknown; the reader clamps to its last page.
                characterOffset: last.textLength ?? .max,
                updatedAt: .now
            ))
            guard !isLocalBook else { return }

            // The service stores no progress it is sent, so this is a courtesy rather than the record.
            try? await session.client.updateProgress(
                workId: work.id,
                chapterId: last.id,
                workProgress: 1,
                chapterProgress: 1,
                sessionId: nil
            )
        }

        /// The book's chapters as the device has them, fetched if it has none.
        private func contents(of workId: Int) async -> [BookChapter] {
            let stored = await store.chapters(workId: workId)

            guard stored.isEmpty, !BookNumbering.isLocal(workId) else { return stored }
            guard
                let fetched = try? await session.client.workContents(id: workId).map(BookChapter.init)
            else { return [] }

            await store.store(chapters: fetched, workId: workId)
            return fetched.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) }
        }

        /// Takes a book out of the reader's library. Removing it is the one thing left that the
        /// service's library state is good for.
        func remove(_ work: Book) async {
            guard !isLocal(work) else { return await deleteLocalBook(work) }
            guard session.isSignedIn else { return }

            works.removeAll { $0.id == work.id }

            do {
                try await session.client.updateLibraryState(workIds: [ work.id ], state: LibraryState.none)
                await persistLibrary()
            } catch {
                // The library the service holds wins, and the message goes on after the reload, which
                // clears it.
                await reload()
                errorMessage = error.localizedDescription
            }
        }

        private func persistLibrary() async {
            await store.replaceLibrary(with: works)
        }

        private func apply(entries: [Book]) {
            guard works != entries else { return }

            works = entries
            Task { await CoverCache.shared.prefetch(entries.compactMap(\.coverURL)) }
        }
    }
}
