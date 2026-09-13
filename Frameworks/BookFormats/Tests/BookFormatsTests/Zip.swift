//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// Writes the archives the tests read, so the reader is checked against bytes rather than against a
/// mock of itself.
///
/// Members are stored rather than deflated, which is one of the two ways a book arrives and the one
/// that needs no compressor. The Zip64 variant writes the wide records a large archive carries, with
/// the ordinary fields left at all ones the way a writer that has outgrown them does.
enum Zip {
    struct File {
        let name: String
        let data: Data

        init(_ name: String, _ contents: String) {
            self.name = name
            self.data = Data(contents.utf8)
        }

        init(_ name: String, _ data: Data) {
            self.name = name
            self.data = data
        }
    }

    static func archive(_ files: [File], wide: Bool = false) -> Data {
        var payload = Data()
        var directory = Data()
        var offsets: [Int] = []

        for file in files {
            offsets.append(payload.count)
            payload += localHeader(file, wide: wide)
            payload += file.data
        }

        for (file, offset) in zip(files, offsets) {
            directory += centralHeader(file, at: offset, wide: wide)
        }

        let start = payload.count
        var archive = payload + directory

        if wide {
            archive += zip64Directory(count: files.count, size: directory.count, at: start)
            archive += zip64Locator(at: start + directory.count)
        }

        archive += endOfDirectory(count: files.count, size: directory.count, at: start, wide: wide)
        return archive
    }

    // MARK: - The records

    private static func localHeader(_ file: File, wide: Bool) -> Data {
        var header = Data()
        let name = Data(file.name.utf8)

        header += number(0x0403_4B50, 4)
        header += number(wide ? 45 : 20, 2)
        header += number(0x800, 2)
        header += number(0, 2)
        header += number(0, 2) + number(0, 2)
        header += number(Int(crc32(file.data)), 4)
        header += number(file.data.count, 4) + number(file.data.count, 4)
        header += number(name.count, 2) + number(0, 2)
        header += name
        return header
    }

    private static func centralHeader(_ file: File, at offset: Int, wide: Bool) -> Data {
        var header = Data()
        let name = Data(file.name.utf8)
        // A writer that has outgrown the ordinary fields leaves them at all ones and puts the real
        // numbers in the extra field.
        let extra = wide ? zip64Extra(size: file.data.count, offset: offset) : Data()
        let stated = wide ? 0xFFFF_FFFF : file.data.count

        header += number(0x0201_4B50, 4)
        header += number(wide ? 45 : 20, 2) + number(wide ? 45 : 20, 2)
        header += number(0x800, 2)
        header += number(0, 2)
        header += number(0, 2) + number(0, 2)
        header += number(Int(crc32(file.data)), 4)
        header += number(stated, 4) + number(stated, 4)
        header += number(name.count, 2) + number(extra.count, 2) + number(0, 2)
        header += number(0, 2) + number(0, 2) + number(0, 4)
        header += number(wide ? 0xFFFF_FFFF : offset, 4)
        header += name + extra
        return header
    }

    private static func zip64Extra(size: Int, offset: Int) -> Data {
        var extra = Data()

        extra += number(0x0001, 2) + number(24, 2)
        extra += number(size, 8) + number(size, 8) + number(offset, 8)
        return extra
    }

    private static func zip64Directory(count: Int, size: Int, at offset: Int) -> Data {
        var record = Data()

        record += number(0x0606_4B50, 4)
        record += number(44, 8)
        record += number(45, 2) + number(45, 2)
        record += number(0, 4) + number(0, 4)
        record += number(count, 8) + number(count, 8)
        record += number(size, 8) + number(offset, 8)
        return record
    }

    private static func zip64Locator(at offset: Int) -> Data {
        var locator = Data()

        locator += number(0x0706_4B50, 4)
        locator += number(0, 4)
        locator += number(offset, 8)
        locator += number(1, 4)
        return locator
    }

    private static func endOfDirectory(count: Int, size: Int, at offset: Int, wide: Bool) -> Data {
        var record = Data()
        let stated = wide ? 0xFFFF : count

        record += number(0x0605_4B50, 4)
        record += number(0, 2) + number(0, 2)
        record += number(stated, 2) + number(stated, 2)
        record += number(size, 4) + number(wide ? 0xFFFF_FFFF : offset, 4)
        record += number(0, 2)
        return record
    }

    // MARK: - Bytes

    private static func number(_ value: Int, _ bytes: Int) -> Data {
        var data = Data()

        for step in 0 ..< bytes { data.append(UInt8((value >> (8 * step)) & 0xFF)) }

        return data
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var result: UInt32 = 0xFFFF_FFFF

        for byte in data {
            result ^= UInt32(byte)

            for _ in 0 ..< 8 {
                result = result & 1 == 1 ? (result >> 1) ^ 0xEDB8_8320 : result >> 1
            }
        }

        return result ^ 0xFFFF_FFFF
    }
}
