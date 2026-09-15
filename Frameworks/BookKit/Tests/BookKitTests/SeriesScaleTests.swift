//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import Testing

@testable import BookKit

/// A series held partly as files and partly from a service, put on one scale.
///
/// Every title here is invented. What matters is the shape: a file counts a work as one place however
/// many volumes it runs to, and a service gives every volume a place of its own.
struct SeriesScaleTests {
    private static let series = "Зимпель"

    /// A negative id is a book off a file; a positive one came from the service.
    private static func book(_ id: Int, _ title: String, _ order: Int?) -> Book {
        Book(
            id: id,
            title: title,
            authorLine: "Имя Фамилия",
            coverURL: nil,
            annotation: nil,
            seriesTitle: series,
            seriesOrder: order
        )
    }

    /// Files alone already count the way a series is printed, so nothing moves.
    @Test
    func aseriesHeldOnlyAsFilesKeepsItsNumbering() {
        let held = [
            Self.book(-1, "Первый", 1),
            Self.book(-2, "Второй. Том 1", 2),
            Self.book(-3, "Второй. Том 2", 2),
            Self.book(-4, "Третий", 3),
        ]

        #expect(SeriesScale.volumes(of: held) == [ -1: 1, -2: 2, -3: 2, -4: 3 ])
    }

    /// The service alone counts every volume, so its figures fold back to the places they stand on.
    @Test
    func aseriesHeldOnlyFromTheServiceFoldsItsVolumesTogether() {
        let held = [
            Self.book(1, "Первый", 1),
            Self.book(2, "Второй (том 1)", 2),
            Self.book(3, "Второй (том 2)", 3),
            Self.book(4, "Третий", 4),
        ]

        #expect(SeriesScale.volumes(of: held) == [ 1: 1, 2: 2, 3: 2, 4: 3 ])
    }

    /// The case that started this: files running up to a place and the service carrying on past it.
    @Test
    func theServicesFiguresAreBroughtOntoTheFilesScale() {
        let held = [
            Self.book(-1, "Первый", 1),
            Self.book(-2, "Второй. Том 1", 2),
            Self.book(-3, "Второй. Том 2", 2),
            Self.book(-4, "Третий", 3),
            // The service counts the four volumes above as four places, so its fifth is the fourth work.
            Self.book(5, "Четвёртый", 5),
            Self.book(6, "Пятый (том 1)", 6),
            Self.book(7, "Пятый (том 2)", 7),
            Self.book(8, "Шестой", 8),
        ]

        let volumes = SeriesScale.volumes(of: held)

        #expect(volumes[5] == 4)
        #expect(volumes[6] == 5)
        #expect(volumes[7] == 5)
        #expect(volumes[8] == 6)
        // And the files are left standing where they were.
        #expect(volumes[-4] == 3)
    }

    /// Two volumes of one work stand on one place, whichever side each came from.
    @Test
    func twoVolumesOfOneWorkShareAPlace() {
        let held = [
            Self.book(-1, "Первый", 1),
            Self.book(-2, "Второй. Том 2", 2),
            Self.book(3, "Второй (том 1)", 2),
        ]

        let volumes = SeriesScale.volumes(of: held)

        #expect(volumes[-2] == volumes[3])
    }

    /// A file's figure is whatever whoever made it wrote there, so the service's word wins.
    @Test
    func theServicesFigureBeatsAfilesWrongOne() {
        let held = [
            Self.book(-1, "Первый", 1),
            Self.book(-2, "Второй", 2),
            // Both files claim the second place; only one of them can be right.
            Self.book(-3, "Третий", 2),
            Self.book(4, "Третий", 3),
        ]

        let volumes = SeriesScale.volumes(of: held)

        #expect(volumes[-2] == 2)
        #expect(volumes[-3] == 3)
        #expect(volumes[4] == 3)
    }

    /// Counted apart, two copies of one volume meet and two volumes of one work do not.
    @Test
    func volumesCountedApartTellCopiesFromVolumes() {
        let held = [
            Self.book(-1, "Первый", 1),
            Self.book(-2, "Второй. Том 2", 2),
            Self.book(3, "Второй (том 1)", 2),
            Self.book(4, "Второй (том 2)", 3),
        ]

        let apart = SeriesScale.volumesApart(of: held)

        #expect(apart[-2] == apart[4])
        #expect(apart[3] != apart[4])
        // And all three still stand on the one place their work takes.
        #expect(SeriesScale.volumes(of: held)[-2] == 2)
        #expect(SeriesScale.volumes(of: held)[3] == 2)
    }

    /// A title that is nothing but a volume word and a figure is still a book of its own, and the gap
    /// between two such books stands.
    @Test
    func titlesThatAreOnlyAvolumeStayApart() {
        let held = [ Self.book(1, "Книга 1", 1), Self.book(5, "Книга 5", 5) ]
        let volumes = SeriesScale.volumes(of: held)

        #expect(volumes[1] == 1)
        #expect(volumes[5] == 5)
    }

    /// A book stating no place at all is left out rather than guessed at.
    @Test
    func abookStatingNoPlaceIsLeftOut() {
        let held = [ Self.book(-1, "Первый", 1), Self.book(-2, "Без места", nil) ]

        #expect(SeriesScale.volumes(of: held)[-2] == nil)
    }

    /// Books outside any series are not numbered.
    @Test
    func abookInNoSeriesIsLeftOut() {
        let loose = Book(id: 9, title: "Сама по себе", authorLine: "Имя Фамилия", coverURL: nil, annotation: nil)

        #expect(SeriesScale.volumes(of: [ loose ]).isEmpty)
    }

    /// Two series in one library are counted apart.
    @Test
    func eachSeriesIsCountedOnItsOwn() {
        let held = [
            Self.book(-1, "Первый", 1),
            Book(
                id: -2,
                title: "Другой первый",
                authorLine: "Имя Фамилия",
                coverURL: nil,
                annotation: nil,
                seriesTitle: "Ворбат",
                seriesOrder: 1
            ),
        ]

        #expect(SeriesScale.volumes(of: held) == [ -1: 1, -2: 1 ])
    }
}
