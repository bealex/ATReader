//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// The little of the zip format that has to be understood to get a book out of an archive.
///
/// FB2 books are handed out zipped more often than not, an EPUB is an archive by definition, and the
/// platform has no public API for reading one. Only what a book needs is here: the central directory,
/// members that are either stored or deflated, and the Zip64 fields a large archive keeps its numbers
/// in. Encryption and multi-disk archives are refused rather than half-supported.
///
/// The sizes are read from the central directory rather than from each local header, because a zip
/// written as a stream leaves them zero in the local header and fills them in afterwards.
public enum ZipArchive {
    /// One member of an archive, located but not yet read.
    struct Entry {
        var name: String
        var isDeflated: Bool
        var localHeaderOffset: Int
        var compressedSize: Int
        var uncompressedSize: Int

        /// Directories are entries too, and a zip made on a Mac carries a second copy of every file
        /// under `__MACOSX` that is a resource fork rather than the file.
        var isFile: Bool {
            !name.hasSuffix("/") && !name.hasPrefix("__MACOSX/")
                && !(name as NSString).lastPathComponent.hasPrefix("._")
        }
    }

    /// True where the bytes open with a local header or an empty archive's end record.
    public static func isArchive(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }

        let signature = integer(data, at: 0, bytes: 4)
        return signature == localHeaderSignature || signature == endOfDirectorySignature
    }

    /// The book inside an archive: the first `.fb2` member, or the largest file where none says so.
    public static func book(in data: Data) throws -> Data {
        let entries = try self.entries(in: data).filter(\.isFile)

        guard !entries.isEmpty else { throw BookFileError.emptyArchive }

        let named = entries.first { $0.name.lowercased().hasSuffix(".fb2") }
        let chosen = named ?? entries.max { $0.uncompressedSize < $1.uncompressedSize }

        guard let chosen else { throw BookFileError.emptyArchive }

        return try contents(of: chosen, in: data)
    }

    // MARK: - Walking the central directory

    static func entries(in data: Data) throws -> [Entry] {
        guard let directory = endOfDirectory(in: data) else { throw BookFileError.malformed("no zip directory") }

        var entries: [Entry] = []
        var cursor = directory.offset

        for _ in 0 ..< directory.count {
            guard
                cursor + centralHeaderLength <= data.count,
                integer(data, at: cursor, bytes: 4) == centralHeaderSignature
            else { throw BookFileError.malformed("damaged zip directory") }

            let flags = integer(data, at: cursor + 8, bytes: 2)
            let method = integer(data, at: cursor + 10, bytes: 2)
            let nameLength = integer(data, at: cursor + 28, bytes: 2)
            let extraLength = integer(data, at: cursor + 30, bytes: 2)
            let commentLength = integer(data, at: cursor + 32, bytes: 2)

            var sizes = Sizes(
                uncompressed: integer(data, at: cursor + 24, bytes: 4),
                compressed: integer(data, at: cursor + 20, bytes: 4),
                localOffset: integer(data, at: cursor + 42, bytes: 4)
            )

            // Bit zero is set on a member that is encrypted, which there is no key for here.
            guard flags & 1 == 0 else { throw BookFileError.protectedArchive }

            // A number the record gives as all ones is too big for it and stands in the Zip64 extra.
            if sizes.overflowed {
                sizes = readZip64(
                    data,
                    at: cursor + centralHeaderLength + nameLength,
                    length: extraLength,
                    given: sizes
                )
            }

            guard !sizes.overflowed else { throw BookFileError.malformed("zip64 sizes missing") }

            entries.append(Entry(
                name: name(data, at: cursor + centralHeaderLength, length: nameLength, isUTF8: flags & 0x800 != 0),
                isDeflated: method == deflated,
                localHeaderOffset: sizes.localOffset,
                compressedSize: sizes.compressed,
                uncompressedSize: sizes.uncompressed
            ))

            cursor += centralHeaderLength + nameLength + extraLength + commentLength
        }

        return entries
    }

    /// One member's bytes, inflated where it was deflated.
    static func contents(of entry: Entry, in data: Data) throws -> Data {
        guard
            entry.isDeflated || entry.compressedSize == entry.uncompressedSize
        else { throw BookFileError.malformed("unsupported zip compression") }

        let header = entry.localHeaderOffset

        guard
            header >= 0,
            header + localHeaderLength <= data.count,
            integer(data, at: header, bytes: 4) == localHeaderSignature
        else { throw BookFileError.malformed("damaged zip member") }

        // The local header carries its own name and extra lengths, which need not match the ones the
        // directory gave for the same member.
        let start =
            header + localHeaderLength
            + integer(data, at: header + 26, bytes: 2)
            + integer(data, at: header + 28, bytes: 2)

        guard start + entry.compressedSize <= data.count else { throw BookFileError.malformed("truncated zip") }

        let payload = data.subdata(in: (data.startIndex + start) ..< (data.startIndex + start + entry.compressedSize))

        guard entry.isDeflated else { return payload }

        do {
            // A zip member is raw DEFLATE, which is what this algorithm reads and writes.
            return try (payload as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw BookFileError.malformed("zip member would not inflate")
        }
    }

    // MARK: - Finding the end of the archive

    private struct Directory {
        var offset: Int
        var count: Int
    }

    /// The end-of-directory record, which stands last and may be followed by a comment of any length.
    private static func endOfDirectory(in data: Data) -> Directory? {
        guard data.count >= endOfDirectoryLength else { return nil }

        let earliest = max(0, data.count - endOfDirectoryLength - maximumCommentLength)

        for start in stride(from: data.count - endOfDirectoryLength, through: earliest, by: -1)
        where integer(data, at: start, bytes: 4) == endOfDirectorySignature {
            if let wide = zip64Directory(in: data, endingAt: start) { return wide }

            let count = integer(data, at: start + 10, bytes: 2)
            let offset = integer(data, at: start + 16, bytes: 4)

            guard offset < data.count else { return nil }

            return Directory(offset: offset, count: count)
        }

        return nil
    }

    /// The Zip64 record behind an end-of-directory whose own fields were too small for the archive.
    ///
    /// Its locator stands immediately before the record it belongs to, which is what makes the wide
    /// record findable without a second scan.
    private static func zip64Directory(in data: Data, endingAt start: Int) -> Directory? {
        let locator = start - zip64LocatorLength

        guard locator >= 0, integer(data, at: locator, bytes: 4) == zip64LocatorSignature else { return nil }

        let record = integer(data, at: locator + 8, bytes: 8)

        guard
            record >= 0,
            record + zip64DirectoryLength <= data.count,
            integer(data, at: record, bytes: 4) == zip64DirectorySignature
        else { return nil }

        let offset = integer(data, at: record + 48, bytes: 8)
        let count = integer(data, at: record + 32, bytes: 8)

        guard offset >= 0, offset < data.count, count >= 0 else { return nil }

        return Directory(offset: offset, count: count)
    }

    /// What a member states about itself, which for a large archive its own record cannot hold.
    private struct Sizes {
        var uncompressed: Int
        var compressed: Int
        var localOffset: Int

        /// True where any of the three was too big for the record and stands elsewhere.
        var overflowed: Bool {
            uncompressed == overflow || compressed == overflow || localOffset == overflow
        }
    }

    /// A member's numbers as its Zip64 extra field gives them.
    ///
    /// The three stand in a fixed order and only the ones that overflowed are present at all, so each
    /// is read exactly where the record itself said its own copy was too small.
    private static func readZip64(_ data: Data, at offset: Int, length: Int, given sizes: Sizes) -> Sizes {
        var sizes = sizes
        var cursor = offset
        let end = min(offset + length, data.count)

        while cursor + 4 <= end {
            let id = integer(data, at: cursor, bytes: 2)
            let size = integer(data, at: cursor + 2, bytes: 2)
            var field = cursor + 4

            guard
                id == zip64ExtraId,
                size >= 0,
                field + size <= end
            else {
                cursor = field + max(0, size)
                continue
            }

            if sizes.uncompressed == overflow, field + 8 <= end {
                sizes.uncompressed = integer(data, at: field, bytes: 8)
                field += 8
            }

            if sizes.compressed == overflow, field + 8 <= end {
                sizes.compressed = integer(data, at: field, bytes: 8)
                field += 8
            }

            if sizes.localOffset == overflow, field + 8 <= end {
                sizes.localOffset = integer(data, at: field, bytes: 8)
            }

            return sizes
        }

        return sizes
    }

    // MARK: - Reading the bytes

    /// A little-endian integer of one to eight bytes.
    private static func integer(_ data: Data, at offset: Int, bytes: Int) -> Int {
        guard offset >= 0, offset + bytes <= data.count else { return -1 }

        var value = 0

        for step in 0 ..< bytes {
            value |= Int(data[data.startIndex + offset + step]) << (8 * step)
        }

        return value
    }

    private static func name(_ data: Data, at offset: Int, length: Int, isUTF8: Bool) -> String {
        guard length > 0, offset + length <= data.count else { return "" }

        let raw = data.subdata(in: (data.startIndex + offset) ..< (data.startIndex + offset + length))
        // Names are UTF-8 only where the member says so; the rest are an old single-byte encoding that
        // agrees with ASCII, which is all a `.fb2` suffix needs.
        // Latin-1 maps every byte, so the fallback always answers.
        return String(bytes: raw, encoding: isUTF8 ? .utf8 : .isoLatin1)
            ?? String(bytes: raw, encoding: .isoLatin1)
            ?? ""
    }

    private static let localHeaderSignature = 0x0403_4B50
    private static let centralHeaderSignature = 0x0201_4B50
    private static let endOfDirectorySignature = 0x0605_4B50
    private static let zip64DirectorySignature = 0x0606_4B50
    private static let zip64LocatorSignature = 0x0706_4B50
    private static let localHeaderLength = 30
    private static let centralHeaderLength = 46
    private static let endOfDirectoryLength = 22
    private static let zip64LocatorLength = 20
    private static let zip64DirectoryLength = 56
    private static let zip64ExtraId = 0x0001
    /// What a 32-bit field holds when the real number stands in the Zip64 extra instead.
    private static let overflow = 0xFFFF_FFFF
    private static let maximumCommentLength = 0xFFFF
    private static let deflated = 8
}

/// An archive walked once, so its members can be read by name without finding the directory again.
///
/// An EPUB is read member by member: the container, the package, the navigation and one file per
/// chapter, each named by a document that came out of the archive before it.
struct ZipReader {
    let entries: [ZipArchive.Entry]

    private let data: Data
    /// Members by the name the archive gives them, and again folded, so a file whose markup disagrees
    /// with its own directory about case still finds its pictures.
    private let byName: [String: ZipArchive.Entry]
    private let byFoldedName: [String: ZipArchive.Entry]

    init(_ data: Data) throws {
        let entries = try ZipArchive.entries(in: data).filter(\.isFile)

        self.data = data
        self.entries = entries
        self.byName = Dictionary(entries.map { ($0.name, $0) }) { first, _ in first }
        self.byFoldedName = Dictionary(entries.map { ($0.name.lowercased(), $0) }) { first, _ in first }
    }

    func has(_ name: String) -> Bool { entry(named: name) != nil }

    /// One member's bytes, or nothing where the archive holds no such file.
    func member(named name: String) -> Data? {
        entry(named: name).flatMap { try? ZipArchive.contents(of: $0, in: data) }
    }

    /// One member read as text, in whichever encoding it turns out to be written in.
    func text(named name: String) -> String? {
        member(named: name).flatMap(Self.text(of:))
    }

    /// Bytes as text: UTF-8, then whatever the document declares, then an encoding that maps anything.
    static func text(of data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }

        let head = String(data: data.prefix(1024), encoding: .isoLatin1) ?? ""

        if head.range(of: "windows-1251", options: .caseInsensitive) != nil {
            return String(data: data, encoding: .windowsCP1251) ?? String(data: data, encoding: .isoLatin1)
        }

        return String(data: data, encoding: .utf16) ?? String(data: data, encoding: .isoLatin1)
    }

    /// A name as the archive spells it, given one an EPUB's own markup used to point at it.
    private func entry(named name: String) -> ZipArchive.Entry? {
        let decoded = name.removingPercentEncoding ?? name

        if let exact = byName[decoded] ?? byName[name] { return exact }

        return byFoldedName[decoded.lowercased()] ?? byFoldedName[name.lowercased()]
    }
}
