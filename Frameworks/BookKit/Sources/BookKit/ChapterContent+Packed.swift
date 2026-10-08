//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// A prepared chapter as bytes, for the copy a device keeps and reads back every time a book opens.
///
/// Two bytes say what this is and which layout it is in, then the fields follow in a fixed order.
/// Whole numbers are written seven bits to a byte, low bits first, with the top bit saying another
/// byte follows; a number that may be negative is folded onto the positives first. Text is its
/// length in UTF-8 and then the bytes. A paragraph opens with a word of flags naming which of its
/// rarer fields follow, so a paragraph of plain text costs its number, its flags and its text.
///
/// A change to what is written takes a new version, and bytes in any other version read as nothing,
/// which sends the chapter back to be prepared again.
extension ChapterContent {
    public func packed() -> Data {
        var writer = PackWriter(roomFor: Self.estimate(paragraphs) + Self.estimate(hyphenated))

        writer.byte(Self.mark)
        writer.byte(Self.version)
        writer.text(language)
        writer.count(paragraphs.count)
        for paragraph in paragraphs { paragraph.pack(into: &writer) }
        writer.count(hyphenated.count)
        for paragraph in hyphenated { paragraph.pack(into: &writer) }
        writer.count(notes.count)

        // In a settled order, so one chapter always packs to the same bytes.
        for (key, note) in notes.sorted(by: { $0.key < $1.key }) {
            writer.text(key)
            writer.text(note.id)
            writer.text(note.marker)
            writer.text(note.text)
        }

        return writer.data
    }

    /// The chapter these bytes hold, or nothing where they aren't this layout or stop short.
    public init?(packed data: Data) {
        let read: ChapterContent? = data.withUnsafeBytes { bytes in
            var reader = PackReader(bytes)

            return try? Self.unpack(&reader)
        }

        guard let read else { return nil }

        self = read
    }

    private static func unpack(_ reader: inout PackReader) throws(PackError) -> ChapterContent {
        guard try reader.byte() == mark, try reader.byte() == version else { throw .unknownLayout }

        let language = try reader.optionalText()
        let paragraphs = try reader.list { reader throws(PackError) in try Paragraph(unpacking: &reader) }
        let hyphenated = try reader.list { reader throws(PackError) in try Paragraph(unpacking: &reader) }
        var notes: [String: BookNote] = [:]

        for _ in 0 ..< (try reader.count()) {
            let key = try reader.text()

            notes[key] = BookNote(id: try reader.text(), marker: try reader.text(), text: try reader.text())
        }

        return ChapterContent(paragraphs: paragraphs, hyphenated: hyphenated, language: language, notes: notes)
    }

    private static let mark: UInt8 = 0xB7
    private static let version: UInt8 = 1

    /// About how many bytes paragraphs pack to: their text, and a little for each one's own fields.
    private static func estimate(_ paragraphs: [Paragraph]) -> Int {
        paragraphs.reduce(0) { $0 + $1.text.utf8.count + 8 }
    }
}

// MARK: - A paragraph

extension Paragraph {
    /// Which of a paragraph's fields follow its text, a bit apiece.
    private struct Has: OptionSet {
        let rawValue: UInt64

        static let centred = Has(rawValue: 1 << 0)
        static let rightToLeft = Has(rawValue: 1 << 1)
        static let rightAligned = Has(rawValue: 1 << 2)
        static let inset = Has(rawValue: 1 << 3)
        static let source = Has(rawValue: 1 << 4)
        static let verse = Has(rawValue: 1 << 5)
        static let picture = Has(rawValue: 1 << 6)
        static let table = Has(rawValue: 1 << 7)
        static let titleLevel = Has(rawValue: 1 << 8)
        static let listLevel = Has(rawValue: 1 << 9)
        static let anchor = Has(rawValue: 1 << 10)
        static let notes = Has(rawValue: 1 << 11)
        static let scripts = Has(rawValue: 1 << 12)
        static let styles = Has(rawValue: 1 << 13)
        static let links = Has(rawValue: 1 << 14)
    }

    /// Which fields this paragraph has anything in.
    private var has: Has {
        let fields: [(Bool, Has)] = [
            (isCentered, .centred), (isRightToLeft, .rightToLeft), (isRightAligned, .rightAligned),
            (isInset, .inset), (isSource, .source), (isVerse, .verse),
            (imageSource != nil, .picture), (table != nil, .table),
            (titleLevel != nil, .titleLevel), (listLevel != nil, .listLevel), (anchor != nil, .anchor),
            (!notes.isEmpty, .notes), (!scripts.isEmpty, .scripts), (!styles.isEmpty, .styles),
            (!links.isEmpty, .links),
        ]

        return fields.reduce(into: Has()) { has, field in
            if field.0 { has.insert(field.1) }
        }
    }

    fileprivate func pack(into writer: inout PackWriter) {
        let has = has

        writer.number(has.rawValue)
        writer.signed(id)
        writer.text(text)

        if let imageSource { writer.text(imageSource) }
        if let table { table.pack(into: &writer) }
        if let titleLevel { writer.signed(titleLevel) }
        if let listLevel { writer.signed(listLevel) }
        if let anchor { writer.text(anchor) }
        if has.contains(.notes) { packNotes(into: &writer) }
        if has.contains(.scripts) { packScripts(into: &writer) }
        if has.contains(.styles) { writer.styles(styles) }
        if has.contains(.links) { packLinks(into: &writer) }
    }

    private func packNotes(into writer: inout PackWriter) {
        writer.count(notes.count)

        for note in notes {
            writer.signed(note.location)
            writer.signed(note.length)
            writer.text(note.noteId)
        }
    }

    private func packScripts(into writer: inout PackWriter) {
        writer.count(scripts.count)

        for script in scripts {
            writer.signed(script.location)
            writer.signed(script.length)

            switch script.place {
                case .below: writer.byte(0)
                case .above: writer.byte(1)
            }
        }
    }

    private func packLinks(into writer: inout PackWriter) {
        writer.count(links.count)

        for link in links {
            writer.signed(link.location)
            writer.signed(link.length)
            writer.text(link.target)
        }
    }

    fileprivate init(unpacking reader: inout PackReader) throws(PackError) {
        let has = Has(rawValue: try reader.number())
        let id = try reader.signed()
        let text = try reader.text()
        let imageSource = has.contains(.picture) ? try reader.text() : nil
        let table = has.contains(.table) ? try BookTable(unpacking: &reader) : nil
        let titleLevel = has.contains(.titleLevel) ? try reader.signed() : nil
        let listLevel = has.contains(.listLevel) ? try reader.signed() : nil
        let anchor = has.contains(.anchor) ? try reader.text() : nil
        var notes: [NoteMark] = []
        var scripts: [ScriptMark] = []
        var links: [LinkMark] = []

        if has.contains(.notes) {
            notes = try reader.list { reader throws(PackError) in
                NoteMark(location: try reader.signed(), length: try reader.signed(), noteId: try reader.text())
            }
        }

        if has.contains(.scripts) {
            scripts = try reader.list { reader throws(PackError) in
                ScriptMark(
                    location: try reader.signed(),
                    length: try reader.signed(),
                    place: try reader.byte() == 1 ? .above : .below
                )
            }
        }

        let styles = has.contains(.styles) ? try reader.styles() : []

        if has.contains(.links) {
            links = try reader.list { reader throws(PackError) in
                LinkMark(location: try reader.signed(), length: try reader.signed(), target: try reader.text())
            }
        }

        self.init(
            id: id,
            text: text,
            isCentered: has.contains(.centred),
            imageSource: imageSource,
            table: table,
            titleLevel: titleLevel,
            notes: notes,
            scripts: scripts,
            styles: styles,
            listLevel: listLevel,
            isRightToLeft: has.contains(.rightToLeft),
            links: links,
            anchor: anchor,
            isRightAligned: has.contains(.rightAligned),
            isInset: has.contains(.inset),
            isSource: has.contains(.source),
            isVerse: has.contains(.verse)
        )
    }
}

// MARK: - A table

extension BookTable {
    fileprivate func pack(into writer: inout PackWriter) {
        writer.count(rows.count)

        for row in rows {
            writer.count(row.count)

            for cell in row {
                writer.text(cell.text)
                writer.styles(cell.styles)
            }
        }

        writer.count(headerRows)
        writer.count(alignments.count)

        for alignment in alignments {
            switch alignment {
                case .leading: writer.byte(0)
                case .center: writer.byte(1)
                case .trailing: writer.byte(2)
            }
        }
    }

    fileprivate init(unpacking reader: inout PackReader) throws(PackError) {
        let rows = try reader.list { reader throws(PackError) in
            try reader.list { reader throws(PackError) in
                Cell(text: try reader.text(), styles: try reader.styles())
            }
        }
        // A plain number: it counts rows already read, and nothing need follow it.
        let headerRows = Int(clamping: try reader.number())
        let alignments = try reader.list { reader throws(PackError) -> Alignment in
            switch try reader.byte() {
                case 1: .center
                case 2: .trailing
                default: .leading
            }
        }

        self.init(rows: rows, headerRows: headerRows, alignments: alignments)
    }
}

// MARK: - Bytes out

private struct PackWriter {
    private var bytes: [UInt8] = []

    init(roomFor count: Int) { bytes.reserveCapacity(count) }

    var data: Data { Data(bytes) }

    mutating func byte(_ value: UInt8) { bytes.append(value) }

    mutating func number(_ value: UInt64) {
        var rest = value

        while rest >= 0x80 {
            bytes.append(UInt8(truncatingIfNeeded: rest) | 0x80)
            rest >>= 7
        }

        bytes.append(UInt8(truncatingIfNeeded: rest))
    }

    /// A number that may be negative, folded so the small ones either side of nought stay short.
    mutating func signed(_ value: Int) {
        number(UInt64(bitPattern: Int64((value << 1) ^ (value >> (Int.bitWidth - 1)))))
    }

    mutating func count(_ value: Int) { number(UInt64(max(0, value))) }

    mutating func text(_ value: String) {
        var value = value

        value.withUTF8 { utf8 in
            count(utf8.count)
            bytes.append(contentsOf: utf8)
        }
    }

    /// Text that may be missing: a byte says whether any follows.
    mutating func text(_ value: String?) {
        byte(value == nil ? 0 : 1)

        if let value { text(value) }
    }

    mutating func styles(_ styles: [StyleMark]) {
        count(styles.count)

        for style in styles {
            signed(style.location)
            signed(style.length)
            switch style.emphasis {
                case .italic: byte(0)
                case .bold: byte(1)
            }
        }
    }
}

// MARK: - Bytes in

private enum PackError: Error {
    case stopsShort
    case unknownLayout
}

private struct PackReader {
    private let bytes: UnsafeRawBufferPointer
    private var at = 0

    init(_ bytes: UnsafeRawBufferPointer) { self.bytes = bytes }

    mutating func byte() throws(PackError) -> UInt8 {
        guard at < bytes.count else { throw .stopsShort }

        defer { at += 1 }

        return bytes[at]
    }

    mutating func number() throws(PackError) -> UInt64 {
        var value: UInt64 = 0
        var shift: UInt64 = 0

        while true {
            let next = try byte()

            value |= UInt64(next & 0x7F) << shift

            guard next & 0x80 != 0 else { return value }

            shift += 7

            guard shift < 64 else { throw .stopsShort }
        }
    }

    mutating func signed() throws(PackError) -> Int {
        let folded = try number()

        return Int(Int64(bitPattern: (folded >> 1) ^ (0 &- (folded & 1))))
    }

    /// A count of things that follow, none of which can take less than a byte: more than are left
    /// is bytes gone wrong, not a list that long.
    mutating func count() throws(PackError) -> Int {
        let value = try number()

        guard value <= UInt64(bytes.count - at) else { throw .stopsShort }

        return Int(value)
    }

    mutating func text() throws(PackError) -> String {
        let length = try count()

        defer { at += length }

        guard
            let text = String(bytes: UnsafeRawBufferPointer(rebasing: bytes[at ..< at + length]), encoding: .utf8)
        else { throw .stopsShort }

        return text
    }

    mutating func optionalText() throws(PackError) -> String? {
        try byte() == 1 ? try text() : nil
    }

    mutating func list<Element>(
        _ element: (inout PackReader) throws(PackError) -> Element
    ) throws(PackError) -> [Element] {
        let count = try count()
        var elements: [Element] = []

        elements.reserveCapacity(count)

        for _ in 0 ..< count { elements.append(try element(&self)) }

        return elements
    }

    mutating func styles() throws(PackError) -> [StyleMark] {
        try list { reader throws(PackError) in
            StyleMark(
                location: try reader.signed(),
                length: try reader.signed(),
                emphasis: try reader.byte() == 1 ? .bold : .italic
            )
        }
    }
}
