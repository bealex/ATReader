//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

#if DEBUG
    import BookKit
    import BookStorage
    import DesignSystem
    import UIKit

    /// An invented library, for looking at the shelf without an account. `-at-demo-library YES`.
    ///
    /// Every author, title and cover here is made up on the spot: nothing the service returned ever goes
    /// in the repository.
    @MainActor
    enum DemoLibrary {
        static var isOn: Bool { UserDefaults.standard.bool(forKey: "at-demo-library") }

        /// The books, with their covers painted into the shared cache the shelf reads from.
        static var books: [Book] {
            (crowded + shelves).enumerated().flatMap { number, shelf in
                shelf.books.enumerated().map { place, entry in
                    book(entry, by: shelf.author, series: shelf.series, shelf: number, place: place)
                }
            }
        }

        private struct Entry {
            let title: String
            let volume: Int?
            /// How far through it the reader is, from nothing to all of it.
            let read: Double
            let isFinished: Bool
            let length: Int
            /// Pale artwork, which prints a pale spine with dark writing on it.
            let isLight: Bool
        }

        private struct Shelf {
            let author: String
            let series: String?
            let books: [Entry]
        }

        private static func entry(
            _ title: String,
            volume: Int? = nil,
            read: Double,
            isFinished: Bool = true,
            length: Int = 600_000,
            isLight: Bool = false
        ) -> Entry {
            Entry(title: title, volume: volume, read: read, isFinished: isFinished, length: length, isLight: isLight)
        }

        /// A long pale series, enough to run onto a second row, and an author mixing pale and dark.
        private static let crowded = [
            Shelf(
                author: "Вера Облакова",
                series: "Белый город",
                books: (1 ... 12).map { volume in
                    entry(
                        "Белый город \(volume)",
                        volume: volume,
                        read: volume <= 7 ? 1 : volume == 8 ? 0.6 : volume == 9 ? 0.2 : 0,
                        isFinished: volume < 12,
                        length: 300_000 + volume * 70_000,
                        isLight: true
                    )
                }
            ),
            Shelf(
                author: "Вера Облакова",
                series: nil,
                books: [
                    entry("Сахарный лёд", read: 0.3, isLight: true),
                    entry("Мел и соль", read: 1, length: 350_000, isLight: true),
                ]
            ),
            Shelf(
                author: "Семён Буков",
                series: "Северные письма",
                books: (1 ... 6).map { volume in
                    entry(
                        "Письмо \(volume)",
                        volume: volume,
                        read: volume <= 3 ? 1 : volume == 4 ? 0.5 : 0,
                        length: 400_000 + volume * 90_000,
                        isLight: volume.isMultiple(of: 2)
                    )
                }
            ),
            Shelf(
                author: "Семён Буков",
                series: "Рыжий кот",
                books: (1 ... 3).map { volume in
                    entry("Рыжий кот \(volume)", volume: volume, read: 1, length: 260_000, isLight: true)
                }
            ),
            Shelf(
                author: "Вера Облакова, Семён Буков",
                series: nil,
                books: [
                    entry("Два берега", read: 0.4, isFinished: false)
                ]
            ),
        ]

        private static let shelves = [
            Shelf(
                author: "Ирина Мельдова",
                series: "Хроники Зимпеля",
                books: [
                    entry("Зимпель. Начало", volume: 1, read: 1, length: 520_000),
                    entry("Зимпель. Перевал", volume: 2, read: 1, length: 640_000),
                    entry("Зимпель. Долгая зима", volume: 3, read: 1, length: 710_000),
                    entry("Зимпель. Оттепель", volume: 4, read: 0.42, length: 690_000),
                    entry("Зимпель. Весна", volume: 5, read: 0, isFinished: false, length: 380_000),
                ]
            ),
            Shelf(
                author: "Ирина Мельдова",
                series: nil,
                books: [
                    entry("Соляной берег", read: 0.7, length: 450_000)
                ]
            ),
            Shelf(
                author: "Глеб Сорокопут",
                series: "Станция «Полынь»",
                books: [
                    entry("Станция «Полынь»", volume: 1, read: 1, length: 820_000),
                    entry("Полынь. Второй круг", volume: 2, read: 1, length: 900_000),
                    entry("Полынь. Сигнал", volume: 3, read: 0.2, length: 870_000),
                    entry("Полынь. Тишина в эфире", volume: 4, read: 0, isFinished: false, length: 300_000),
                ]
            ),
            Shelf(
                author: "Глеб Сорокопут",
                series: nil,
                books: [
                    entry("Железный сад", read: 1, length: 400_000)
                ]
            ),
            Shelf(
                author: "Анна Верескова",
                series: nil,
                books: [
                    entry("Дом с жёлтыми ставнями", read: 0.55, length: 350_000),
                    entry("Ноябрьские письма", read: 1, length: 280_000),
                    entry("Тихая вода", read: 0, length: 500_000),
                ]
            ),
            Shelf(
                author: "Пётр Лаптев",
                series: "Инженер Сомов",
                books: [
                    entry("Инженер Сомов", volume: 1, read: 1, length: 760_000),
                    entry("Сомов. Мастерская", volume: 2, read: 1, length: 780_000),
                    entry("Сомов. Паровой город", volume: 4, read: 1, length: 800_000),
                    entry("Сомов. Мост", volume: 5, read: 1, length: 820_000),
                    entry("Сомов. Новый цех", volume: 6, read: 0.1, isFinished: false, length: 420_000),
                ]
            ),
            Shelf(
                author: "Ника Звонарёва",
                series: "Лисья тропа",
                books: [
                    entry("Лисья тропа", volume: 1, read: 1, length: 560_000),
                    entry("Лисья тропа. Нора", volume: 2, read: 1, length: 590_000),
                ]
            ),
            Shelf(
                author: "Tom Ashgrove",
                series: nil,
                books: [
                    entry("The Lantern Road", read: 0.3, length: 610_000),
                    entry("Salt and Iron", read: 1, length: 480_000),
                ]
            ),
        ]

        private static func book(_ entry: Entry, by author: String, series: String?, shelf: Int, place: Int) -> Book {
            let id = 900_000 + shelf * 100 + place
            let url = URL(string: "demo://cover/\(id)")

            if let url, CoverImages.image(for: url) == nil {
                CoverImages.remember(cover(entry.title, by: author, hue: hue(of: id), isLight: entry.isLight), for: url)
            }

            return Book(
                id: id,
                title: entry.title,
                authorLine: author,
                coverURL: url,
                annotation: nil,
                seriesTitle: series,
                seriesOrder: entry.volume,
                textLength: entry.length,
                isFinished: entry.isFinished,
                // Earlier shelves updated more recently, so they stand first.
                lastUpdateTime: Date(timeIntervalSinceNow: -Double(shelf * 86_400 * 3 - place * 3_600)),
                readingProgress: entry.read,
                hasStartedReading: entry.read > 0
            )
        }

        /// A different colour for every book, spread round the wheel.
        private static func hue(of id: Int) -> CGFloat {
            CGFloat((id * 37) % 360) / 360
        }

        /// The four colours an invented cover is painted in: its two grounds, its shape and its lettering.
        private struct Palette {
            let top: UIColor
            let bottom: UIColor
            let shape: UIColor
            let ink: UIColor

            init(hue: CGFloat, isLight: Bool) {
                let next = (hue + 0.12).truncatingRemainder(dividingBy: 1)
                let opposite = (hue + 0.5).truncatingRemainder(dividingBy: 1)

                if isLight {
                    top = UIColor(hue: hue, saturation: 0.12, brightness: 0.98, alpha: 1)
                    bottom = UIColor(hue: next, saturation: 0.25, brightness: 0.88, alpha: 1)
                    shape = UIColor(hue: opposite, saturation: 0.45, brightness: 0.75, alpha: 0.8)
                    ink = UIColor(white: 0.2, alpha: 1)
                } else {
                    top = UIColor(hue: hue, saturation: 0.55, brightness: 0.55, alpha: 1)
                    bottom = UIColor(hue: next, saturation: 0.7, brightness: 0.3, alpha: 1)
                    shape = UIColor(hue: opposite, saturation: 0.4, brightness: 0.95, alpha: 0.8)
                    ink = .white
                }
            }
        }

        /// An invented cover: two colours, a shape between them, the title above and the author below.
        private static func cover(_ title: String, by author: String, hue: CGFloat, isLight: Bool) -> UIImage {
            let unit = Design.Space.unit
            let size = CGSize(width: unit * 66, height: unit * 99)
            let palette = Palette(hue: hue, isLight: isLight)
            let style = NSMutableParagraphStyle()
            // Twice the point size rather than the screen's three times: the cover cache is bounded by
            // bytes, and forty-odd covers at three times would push the first of them out again.
            let format = UIGraphicsImageRendererFormat()

            style.alignment = .center
            format.scale = 2

            return UIGraphicsImageRenderer(size: size, format: format).image { drawing in
                let context = drawing.cgContext

                if let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [ palette.top.cgColor, palette.bottom.cgColor ] as CFArray,
                    locations: [ 0, 1 ]
                ) {
                    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
                }

                palette.shape.setFill()
                context.fillEllipse(in: CGRect(x: unit * 15, y: unit * 36, width: unit * 36, height: unit * 36))

                NSAttributedString(
                    string: title,
                    attributes: [
                        .font: UIFont(name: "Georgia-Bold", size: 22) ?? .boldSystemFont(ofSize: 22),
                        .foregroundColor: palette.ink,
                        .paragraphStyle: style,
                    ]
                )
                .draw(in: CGRect(x: unit * 5, y: unit * 8, width: size.width - unit * 10, height: unit * 27))

                NSAttributedString(
                    string: author,
                    attributes: [
                        .font: UIFont(name: "Georgia", size: 14) ?? .systemFont(ofSize: 14),
                        .foregroundColor: palette.ink.withAlphaComponent(0.85),
                        .paragraphStyle: style,
                    ]
                )
                .draw(
                    in: CGRect(
                        x: unit * 5,
                        y: size.height - unit * 15,
                        width: size.width - unit * 10,
                        height: unit * 10
                    )
                )
            }
        }
    }
#endif
