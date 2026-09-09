//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import Testing

@testable import Litres

/// Reading the service's answers.
///
/// The JSON here is written to the shape the service uses and filled with invented values. Nothing a
/// service returned goes in this repository.
struct LitresLibraryTests {
    private static let page = """
        {
          "status": 200,
          "error": null,
          "payload": {
            "pagination": {
              "next_page": "/api/users/me/arts?limit=100&after=PmR0OjIwMjU%3D",
              "previous_page": null
            },
            "data": [
              {
                "id": 111,
                "uuid": "aaaaaaaa-0000-0000-0000-000000000000",
                "title": "Первая выдуманная книга",
                "cover_url": "https://example.invalid/1.jpg",
                "art_type": 0,
                "symbols_count": 1000,
                "language_code": "ru",
                "last_updated_at": "2025-12-30T18:51:23"
              },
              {
                "id": 222,
                "uuid": null,
                "title": "Что-то не для чтения",
                "cover_url": null,
                "art_type": 4,
                "symbols_count": null,
                "language_code": "ru",
                "last_updated_at": null
              }
            ]
          }
        }
        """

    private static let files = """
        {
          "status": 200,
          "error": null,
          "payload": {
            "data": [
              {
                "file_type": "unknown",
                "files": [
                  { "id": 987, "filename": "Author_A._Title.zip", "extension": "fb2.zip", "size": 900 },
                  { "id": 987, "filename": "Author_A._Title.zip", "extension": "epub", "size": 800 }
                ]
              }
            ]
          }
        }
        """

    private static func decode<Payload: Decodable>(_ json: String) throws -> Payload {
        let envelope = try JSONDecoder.litres.decode(LitresEnvelope<Payload>.self, from: Data(json.utf8))

        return try #require(envelope.payload)
    }

    @Test
    func aLibraryPageIsRead() throws {
        let payload: LitresLibraryPayload = try Self.decode(Self.page)

        #expect(payload.data.count == 2)
        #expect(payload.data[0].id == 111)
        #expect(payload.data[0].title == "Первая выдуманная книга")
        #expect(payload.data[0].symbolsCount == 1000)
    }

    /// Only a book is a book. The library carries other things the app has no page for.
    @Test
    func onlyTextIsSomethingToRead() throws {
        let payload: LitresLibraryPayload = try Self.decode(Self.page)

        #expect(payload.data[0].isText)
        #expect(!payload.data[1].isText)
    }

    /// A moment arrives with no zone on the end of it, and is read as one.
    @Test
    func aMomentIsReadWithoutAZone() throws {
        let payload: LitresLibraryPayload = try Self.decode(Self.page)
        let when = try #require(payload.data[0].updatedAt)
        var calendar = Calendar(identifier: .gregorian)

        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        #expect(calendar.component(.year, from: when) == 2025)
        #expect(calendar.component(.hour, from: when) == 18)
        #expect(payload.data[1].updatedAt == nil)
    }

    /// The next page is followed exactly as it came, with only its prefix put right.
    ///
    /// The path arrives under `/api/`, which the API does not answer on. Everything after that is left
    /// alone on purpose: the cursor is base64, and one taken apart and put back loses its `+` to a
    /// space, so the service reads a cursor that means something else and refuses the request.
    @Test
    func theNextPageIsFollowedExactlyAsItCame() throws {
        let api = try #require(URL(string: "https://api.litres.ru"))
        let payload: LitresLibraryPayload = try Self.decode(Self.page)
        let next = try #require(LitresClient.next(after: payload.pagination?.nextPage, api: api))

        #expect(
            next.absoluteString == "https://api.litres.ru/foundation/api/users/me/arts?limit=100&after=PmR0OjIwMjU%3D"
        )
        #expect(LitresClient.next(after: nil, api: api) == nil)
    }

    /// The one the service actually sends: base64 with a plus in it.
    @Test
    func aCursorKeepsItsPlus() throws {
        let api = try #require(URL(string: "https://api.litres.ru"))
        let path = "/api/users/me/arts?limit=24&after=PmR0OjIwMjUtMDItMTYgMDc6MTE6MDV%2BaTo3MDYyMDcxNQ%3D%3D"
        let next = try #require(LitresClient.next(after: path, api: api))

        #expect(next.absoluteString.contains("%2B"), "the plus was decoded, and a bare plus is a space")
        #expect(next.absoluteString.hasSuffix("%3D%3D"))
    }

    @Test
    func everyFormatIsOneFile() throws {
        let payload: LitresFilesPayload = try Self.decode(Self.files)
        let all = payload.data.flatMap(\.files)

        #expect(all.count == 2)
        // One id for the work, and the format alone tells the two apart.
        #expect(Set(all.map(\.id)) == [ 987 ])
        #expect(all.map(\.format) == [ "fb2.zip", "epub" ])
    }

    /// The name the service reports always ends in `.zip`; the one a download asks for ends in the
    /// format, whatever that is.
    @Test
    func aDownloadIsNamedForItsFormat() throws {
        let payload: LitresFilesPayload = try Self.decode(Self.files)
        let all = payload.data.flatMap(\.files)

        #expect(all[0].downloadName == "Author_A._Title.fb2.zip")
        #expect(all[1].downloadName == "Author_A._Title.epub")
    }

    @Test
    func aDownloadStandsUnderTheWorkAndItsFile() throws {
        let payload: LitresFilesPayload = try Self.decode(Self.files)
        let client = LitresClient(configuration: .init(userAgent: "test"))
        let url = client.downloadURL(art: 555, file: payload.data[0].files[0])

        #expect(url.absoluteString == "https://www.litres.ru/download_book/555/987/Author_A._Title.fb2.zip")
    }
}
