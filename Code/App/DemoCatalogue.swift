//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

#if DEBUG
    import BookKit
    import Foundation

    /// A made-up library of any size, for seeing how the shelf copes with a big one.
    ///
    /// The same count always makes the same library: every choice comes off one seeded generator, so a
    /// scroll measured today can be measured again tomorrow against the same books.
    enum DemoCatalogue {
        static func books(_ count: Int) -> [Book] {
            var random = Seeded(seed: 2390)
            var books: [Book] = []
            var writer = 0

            while books.count < count {
                let author = name(writer, random: &random)
                let updated = Date(timeIntervalSinceNow: -Double(writer) * day)

                for run in 0 ..< random.next(in: 0 ... 3) {
                    let series = seriesName(writer * 7 + run, random: &random)
                    let volumes = random.next(in: 2 ... 14)
                    let read = random.next(in: 0 ... volumes)
                    let shape = shapes[random.next(in: 0 ... shapes.count - 1)]
                    let isLight = random.next(in: 0 ... 9) < 4

                    for volume in 1 ... volumes {
                        books.append(book(Made(
                            id: books.count,
                            title:
                                "\(series) \(volume). \(subtitles[random.next(in: 0 ... subtitles.count - 1)])",
                            author: coAuthored(author, writer: writer, random: &random),
                            series: series,
                            volume: volume,
                            progress: volume <= read
                                ? 1 : volume == read + 1 ? Double(random.next(in: 0 ... 9)) / 10 : 0,
                            isFinished: volume < volumes || random.next(in: 0 ... 3) > 0,
                            length: random.next(in: 150 ... 1_500) * 1_000,
                            shape: shape,
                            isLight: isLight,
                            updated: updated.addingTimeInterval(-Double(volumes - volume) * hour)
                        )))
                    }
                }

                for alone in 0 ..< random.next(in: 0 ... 4) {
                    let title = "\(standalone[random.next(in: 0 ... standalone.count - 1)]) \(alone + 1)"

                    books.append(book(Made(
                        id: books.count,
                        title: title,
                        author: author,
                        series: nil,
                        volume: nil,
                        progress: [ 0, 0.3, 1, 1 ][random.next(in: 0 ... 3)],
                        isFinished: true,
                        length: random.next(in: 150 ... 1_500) * 1_000,
                        shape: shapes[random.next(in: 0 ... shapes.count - 1)],
                        isLight: random.next(in: 0 ... 9) < 4,
                        updated: updated.addingTimeInterval(-Double(alone) * hour)
                    )))
                }

                writer += 1
            }

            return Array(books.prefix(count))
        }

        private static let day: TimeInterval = 86_400
        private static let hour: TimeInterval = 3_600

        /// The shapes a cover comes in, how many times taller than wide.
        private static let shapes = [ 1.4, 1.5, 1.5, 1.5, 1.6 ]

        /// Everything one made-up book is made of.
        private struct Made {
            let id: Int
            let title: String
            let author: String
            let series: String?
            let volume: Int?
            let progress: Double
            let isFinished: Bool
            let length: Int
            let shape: Double
            let isLight: Bool
            let updated: Date
        }

        private static func book(_ made: Made) -> Book {
            let number = 1_000_000 + made.id

            return Book(
                id: number,
                title: made.title,
                authorLine: made.author,
                coverURL: DemoLibrary.coverURL(
                    id: number,
                    title: made.title,
                    author: made.author,
                    isLight: made.isLight,
                    shape: made.shape
                ),
                annotation: nil,
                seriesTitle: made.series,
                seriesOrder: made.volume,
                textLength: made.length,
                isFinished: made.isFinished,
                lastUpdateTime: made.updated,
                readingProgress: made.progress,
                hasStartedReading: made.progress > 0
            )
        }

        /// A writer's name, a man's or a woman's, made of parts that don't repeat for a long while.
        private static func name(_ writer: Int, random: inout Seeded) -> String {
            let isWoman = random.next(in: 0 ... 1) == 1
            let given = isWoman ? womenNames : menNames
            let family = isWoman ? womenSurnames : menSurnames

            return "\(given[writer % given.count]) \(family[(writer * 7 + writer / family.count) % family.count])"
        }

        /// One book in twenty written with somebody else, named after the writer.
        private static func coAuthored(_ author: String, writer: Int, random: inout Seeded) -> String {
            guard random.next(in: 0 ... 19) == 0 else { return author }

            return
                "\(author), \(menNames[(writer + 3) % menNames.count]) \(menSurnames[(writer + 11) % menSurnames.count])"
        }

        private static func seriesName(_ number: Int, random: inout Seeded) -> String {
            let first = seriesFirst[random.next(in: 0 ... seriesFirst.count - 1)]
            let second = seriesSecond[(number + random.next(in: 0 ... seriesSecond.count - 1)) % seriesSecond.count]

            return "\(first) \(second)"
        }

        private static let menNames = [
            "Аркадий", "Борис", "Вадим", "Глеб", "Денис", "Егор", "Захар", "Игорь", "Кирилл", "Лев",
            "Макар", "Никита", "Олег", "Павел", "Роман", "Семён", "Тимур", "Фёдор", "Юрий", "Ярослав",
        ]

        private static let womenNames = [
            "Алиса", "Вера", "Галина", "Дарья", "Евгения", "Зоя", "Инна", "Кира", "Лидия", "Марина",
            "Нина", "Ольга", "Полина", "Раиса", "Софья", "Таисия", "Ульяна", "Юлия", "Яна", "Ирина",
        ]

        private static let menSurnames = [
            "Буков", "Воронцов", "Грачёв", "Дубов", "Ельцов", "Жуков", "Зимин", "Ивлев", "Клёнов", "Лосев",
            "Мухин", "Никонов", "Орлов", "Панин", "Рябов", "Сомов", "Тихонов", "Устинов", "Филин", "Чижов",
            "Шаров", "Щукин", "Юдин", "Яковлев", "Белов", "Волков", "Гусев",
        ]

        private static let womenSurnames = [
            "Облакова", "Верескова", "Звонарёва", "Мельдова", "Грачёва", "Дубова", "Зимина", "Лосева",
            "Орлова", "Панина", "Рябова", "Сомова", "Тихонова", "Филина", "Чижова", "Шарова", "Юдина",
            "Белова", "Волкова", "Гусева", "Жукова", "Клёнова", "Мухина",
        ]

        private static let seriesFirst = [
            "Хроники", "Тропа", "Дом", "Город", "Остров", "Мост", "Ветер", "Сад", "Берег", "Порог",
        ]

        private static let seriesSecond = [
            "Зимпеля", "Полыни", "Сомова", "Серебра", "Ольхи", "Туманов", "Крапивы", "Янтаря", "Сов", "Льда",
            "Вереска", "Грозы", "Камня", "Лисиц", "Мха",
        ]

        private static let subtitles = [
            "Начало", "Перевал", "Долгая зима", "Оттепель", "Весна", "Сигнал", "Тишина", "Мастерская", "Мост",
            "Нора", "Северные письма", "Новый цех", "Второй круг", "Огни", "Дорога домой", "Переправа",
        ]

        private static let standalone = [
            "Сахарный лёд", "Мел и соль", "Соляной берег", "Железный сад", "Тихая вода", "Ноябрьские письма",
            "Дом с жёлтыми ставнями", "Два берега", "Синий трамвай", "Бумажный маяк",
        ]
    }

    /// A small generator that gives the same numbers for the same seed, which the system's does not.
    private struct Seeded {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next(in range: ClosedRange<Int>) -> Int {
            // SplitMix64: fast, and plenty good for picking names.
            state &+= 0x9E37_79B9_7F4A_7C15

            var mixed = state

            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            mixed ^= mixed >> 31

            return range.lowerBound + Int(mixed % UInt64(range.count))
        }
    }
#endif
