//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// A composed column, written down so it need not be composed again.
///
/// Breaking a chapter into lines is the expensive half of laying one out, and it depends on the text
/// and the setting rather than on where the chapter starts on its page. So the lines are what is kept,
/// and cutting them into pages, which does depend on that, is done afresh each time and costs little.
///
/// A line standing for a picture is not written down: what it holds is a decoded image, and a chapter
/// carrying one is composed the long way.
extension ColumnComposer.Line: Codable {
    private enum Key: String, CodingKey {
        case at, length, starts, ends, hyphen, heading, air, justified
        case height, baseline, origin, width, setting, reason, gapMultiple, gaps
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: Key.self)

        self.init(
            characters: NSRange(
                location: try values.decode(Int.self, forKey: .at),
                length: try values.decode(Int.self, forKey: .length)
            ),
            startsParagraph: try values.decode(Bool.self, forKey: .starts),
            endsParagraph: try values.decode(Bool.self, forKey: .ends),
            endsWithHyphen: try values.decode(Bool.self, forKey: .hyphen),
            isHeading: try values.decode(Bool.self, forKey: .heading),
            titleAir: try values.decode(CGFloat.self, forKey: .air),
            isJustified: try values.decode(Bool.self, forKey: .justified),
            height: try values.decode(CGFloat.self, forKey: .height),
            baseline: try values.decode(CGFloat.self, forKey: .baseline),
            origin: try values.decode(CGFloat.self, forKey: .origin),
            width: try values.decode(CGFloat.self, forKey: .width),
            setting: try values.decodeIfPresent(Setting.self, forKey: .setting),
            shortReason: try values.decodeIfPresent(String.self, forKey: .reason),
            gapMultiple: try values.decode(CGFloat.self, forKey: .gapMultiple),
            gaps: try values.decode(Int.self, forKey: .gaps)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Key.self)

        try values.encode(characters.location, forKey: .at)
        try values.encode(characters.length, forKey: .length)
        try values.encode(startsParagraph, forKey: .starts)
        try values.encode(endsParagraph, forKey: .ends)
        try values.encode(endsWithHyphen, forKey: .hyphen)
        try values.encode(isHeading, forKey: .heading)
        try values.encode(titleAir, forKey: .air)
        try values.encode(isJustified, forKey: .justified)
        try values.encode(height, forKey: .height)
        try values.encode(baseline, forKey: .baseline)
        try values.encode(origin, forKey: .origin)
        try values.encode(width, forKey: .width)
        try values.encodeIfPresent(setting, forKey: .setting)
        try values.encodeIfPresent(shortReason, forKey: .reason)
        try values.encode(gapMultiple, forKey: .gapMultiple)
        try values.encode(gaps, forKey: .gaps)
    }
}

extension ColumnComposer.Line.Setting: Codable {
    private enum Key: String, CodingKey {
        case at, length, start, content, fill, holdsFirstGap, drawsHyphen
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: Key.self)

        self.init(
            paragraph: NSRange(
                location: try values.decode(Int.self, forKey: .at),
                length: try values.decode(Int.self, forKey: .length)
            ),
            start: try values.decode(Int.self, forKey: .start),
            content: try values.decode(Int.self, forKey: .content),
            fill: try values.decode(LineFill.self, forKey: .fill),
            holdsFirstGap: try values.decode(Bool.self, forKey: .holdsFirstGap),
            drawsHyphen: try values.decode(Bool.self, forKey: .drawsHyphen)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Key.self)

        try values.encode(paragraph.location, forKey: .at)
        try values.encode(paragraph.length, forKey: .length)
        try values.encode(start, forKey: .start)
        try values.encode(content, forKey: .content)
        try values.encode(fill, forKey: .fill)
        try values.encode(holdsFirstGap, forKey: .holdsFirstGap)
        try values.encode(drawsHyphen, forKey: .drawsHyphen)
    }
}

extension ColumnComposer {
    /// What the store holds for one chapter at one setting.
    struct Column: Codable {
        let lines: [Line]
    }

    /// True where every line can be written down. A picture is a decoded image and is not.
    static func isKeepable(_ lines: [Line]) -> Bool {
        lines.allSatisfy { $0.image == nil }
    }
}
