//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// One work in the reader's own Litres library.
public struct LitresArt: Sendable, Equatable, Identifiable, Decodable {
    public let id: Int
    public let uuid: String?
    public let title: String
    public let coverURL: URL?
    /// What kind of thing it is. Zero is a book to read; the rest are things this app has no page for.
    public let artType: Int
    public let symbolsCount: Int?
    public let languageCode: String?
    /// When the service last changed it, which is what tells a copy already on the device that it is
    /// out of date.
    public let updatedAt: Date?

    public var isText: Bool { artType == Self.textArtType }

    static let textArtType = 0

    enum CodingKeys: String, CodingKey {
        case id
        case uuid
        case title
        case coverURL = "cover_url"
        case artType = "art_type"
        case symbolsCount = "symbols_count"
        case languageCode = "language_code"
        case updatedAt = "last_updated_at"
    }
}

/// One file the service will hand over for a work.
///
/// Every format shares the work's single file id: what picks between them is ``format`` alone, which
/// is also what the download's own name ends in.
public struct LitresFile: Sendable, Equatable, Decodable {
    public let id: Int
    public let filename: String
    /// `fb2.zip`, `epub`, `a4.pdf`. Not a path extension: several carry a dot of their own.
    public let format: String
    public let size: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case filename
        case format = "extension"
        case size
    }

    /// What the service calls this file in a download's path.
    ///
    /// The name it reports always ends in `.zip` whatever the format is, so the last piece of it comes
    /// off and the format goes on in its place.
    public var downloadName: String {
        let base = filename.contains(".") ? String(filename[..<filename.lastIndex(of: ".")!]) : filename

        return "\(base).\(format)"
    }
}

/// One page of a library, and where the next one stands.
public struct LitresLibraryPage: Sendable, Equatable {
    public let arts: [LitresArt]
    /// The service pages by cursor rather than by number: a library is walked from one page to the
    /// next and never jumped into. Nothing here means the walk is over.
    ///
    /// A whole address rather than the cursor out of it. The cursor is base64 and carries `+` and `=`,
    /// and taking it apart only to put it back means re-encoding it: a `+` left bare in a query is a
    /// space to the server, and the cursor arrives meaning something else.
    public let next: URL?
}

/// What every answer from the service is wrapped in.
struct LitresEnvelope<Payload: Decodable>: Decodable {
    let status: Int?
    let payload: Payload?
}

struct LitresLibraryPayload: Decodable {
    let data: [LitresArt]
    let pagination: Pagination?

    enum CodingKeys: String, CodingKey {
        case data
        case pagination
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        data = (try container.decodeIfPresent([ Lenient<LitresArt> ].self, forKey: .data) ?? []).compactMap(\.value)
        pagination = try container.decodeIfPresent(Pagination.self, forKey: .pagination)
    }

    struct Pagination: Decodable {
        let nextPage: String?

        enum CodingKeys: String, CodingKey {
            case nextPage = "next_page"
        }
    }
}

struct LitresFilesPayload: Decodable {
    let data: [Group]

    enum CodingKeys: String, CodingKey {
        case data
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        data = (try container.decodeIfPresent([ Lenient<Group> ].self, forKey: .data) ?? []).compactMap(\.value)
    }

    struct Group: Decodable {
        let files: [LitresFile]

        enum CodingKeys: String, CodingKey {
            case files
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let listed = try container.decodeIfPresent([ Lenient<LitresFile> ].self, forKey: .files) ?? []

            files = listed.compactMap(\.value)
        }
    }
}

/// A value that may not decode, kept out of the way of the ones that do.
///
/// A list of ten files with one entry this app cannot read is not a broken answer, and treating it as
/// one loses the book. Whatever fails is dropped and the rest stands.
struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

extension JSONDecoder {
    /// The service writes a moment as `2025-12-30T18:51:23`, with no zone on the end of it.
    static var litres: JSONDecoder {
        let decoder = JSONDecoder()
        let formatter = DateFormatter()

        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        decoder.dateDecodingStrategy = .formatted(formatter)
        return decoder
    }
}
