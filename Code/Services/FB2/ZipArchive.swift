//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// The little of the zip format that has to be understood to get one book out of an archive.
///
/// FB2 books are handed out zipped more often than not, and the platform has no public API for reading
/// a zip. Only what a book needs is here: the central directory, and members that are either stored or
/// deflated. Zip64, encryption and multi-disk archives are refused rather than half-supported.
///
/// The sizes are read from the central directory rather than from each local header, because a zip
/// written as a stream leaves them zero in the local header and fills them in afterwards.
enum ZipArchive {
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
    static func isArchive(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }

        let signature = integer(data, at: 0, bytes: 4)
        return signature == localHeaderSignature || signature == endOfDirectorySignature
    }

    /// The book inside an archive: the first `.fb2` member, or the largest file where none says so.
    static func book(in data: Data) throws -> Data {
        let entries = try self.entries(in: data).filter(\.isFile)

        guard !entries.isEmpty else { throw FB2Error.emptyArchive }

        let named = entries.first { $0.name.lowercased().hasSuffix(".fb2") }
        let chosen = named ?? entries.max { $0.uncompressedSize < $1.uncompressedSize }

        guard let chosen else { throw FB2Error.emptyArchive }

        return try contents(of: chosen, in: data)
    }

    // MARK: - Walking the central directory

    static func entries(in data: Data) throws -> [Entry] {
        guard let directory = endOfDirectory(in: data) else { throw FB2Error.malformed("no zip directory") }

        var entries: [Entry] = []
        var cursor = directory.offset

        for _ in 0 ..< directory.count {
            guard
                cursor + centralHeaderLength <= data.count,
                integer(data, at: cursor, bytes: 4) == centralHeaderSignature
            else { throw FB2Error.malformed("damaged zip directory") }

            let flags = integer(data, at: cursor + 8, bytes: 2)
            let method = integer(data, at: cursor + 10, bytes: 2)
            let compressed = integer(data, at: cursor + 20, bytes: 4)
            let uncompressed = integer(data, at: cursor + 24, bytes: 4)
            let nameLength = integer(data, at: cursor + 28, bytes: 2)
            let extraLength = integer(data, at: cursor + 30, bytes: 2)
            let commentLength = integer(data, at: cursor + 32, bytes: 2)
            let localOffset = integer(data, at: cursor + 42, bytes: 4)

            // Bit zero is set on a member that is encrypted, which there is no key for here.
            guard flags & 1 == 0 else { throw FB2Error.protectedArchive }
            // A size the directory gives as all ones lives in a Zip64 field this doesn't read.
            guard
                compressed != 0xFFFF_FFFF,
                uncompressed != 0xFFFF_FFFF
            else {
                throw FB2Error.malformed("zip64 archive")
            }

            entries.append(Entry(
                name: name(data, at: cursor + centralHeaderLength, length: nameLength, isUTF8: flags & 0x800 != 0),
                isDeflated: method == deflated,
                localHeaderOffset: localOffset,
                compressedSize: compressed,
                uncompressedSize: uncompressed
            ))

            cursor += centralHeaderLength + nameLength + extraLength + commentLength
        }

        return entries
    }

    /// One member's bytes, inflated where it was deflated.
    static func contents(of entry: Entry, in data: Data) throws -> Data {
        guard
            entry.isDeflated || entry.compressedSize == entry.uncompressedSize
        else { throw FB2Error.malformed("unsupported zip compression") }

        let header = entry.localHeaderOffset

        guard
            header + localHeaderLength <= data.count,
            integer(data, at: header, bytes: 4) == localHeaderSignature
        else { throw FB2Error.malformed("damaged zip member") }

        // The local header carries its own name and extra lengths, which need not match the ones the
        // directory gave for the same member.
        let start =
            header + localHeaderLength
            + integer(data, at: header + 26, bytes: 2)
            + integer(data, at: header + 28, bytes: 2)

        guard start + entry.compressedSize <= data.count else { throw FB2Error.malformed("truncated zip") }

        let payload = data.subdata(in: (data.startIndex + start) ..< (data.startIndex + start + entry.compressedSize))

        guard entry.isDeflated else { return payload }

        do {
            // A zip member is raw DEFLATE, which is what this algorithm reads and writes.
            return try (payload as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw FB2Error.malformed("zip member would not inflate")
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
            let count = integer(data, at: start + 10, bytes: 2)
            let offset = integer(data, at: start + 16, bytes: 4)

            guard offset < data.count else { return nil }

            return Directory(offset: offset, count: count)
        }

        return nil
    }

    // MARK: - Reading the bytes

    /// A little-endian integer of one to four bytes.
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
        return String(data: raw, encoding: isUTF8 ? .utf8 : .isoLatin1)
            ?? String(decoding: raw, as: UTF8.self)
    }

    private static let localHeaderSignature = 0x0403_4B50
    private static let centralHeaderSignature = 0x0201_4B50
    private static let endOfDirectorySignature = 0x0605_4B50
    private static let localHeaderLength = 30
    private static let centralHeaderLength = 46
    private static let endOfDirectoryLength = 22
    private static let maximumCommentLength = 0xFFFF
    private static let deflated = 8
}
