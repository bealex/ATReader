//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// The little of a book's stylesheets that changes what its text says rather than how it looks.
///
/// The reader sets every book in the face, size and measure the reader chose, so a publisher's CSS is
/// ignored but for the four things it is the only record of: which of its classes centre a line, which
/// slant it, which set it bold, and which turn it round. A book marks its scene breaks and its
/// epigraphs with a class and nothing else, so without this they arrive as ordinary paragraphs.
struct EpubStyles {
    private(set) var centered: Set<String> = []
    private(set) var rightAligned: Set<String> = []
    /// Classes set in from both edges, which is how a book marks a passage quoted at length.
    private(set) var inset: Set<String> = []
    private(set) var italic: Set<String> = []
    private(set) var bold: Set<String> = []
    private(set) var rightToLeft: Set<String> = []

    /// Every stylesheet the book's manifest lists, read as one.
    static func read(_ package: EpubPackage, from archive: ZipReader) -> EpubStyles {
        var styles = EpubStyles()

        for item in package.items.values where item.mediaType.contains("css") {
            guard let text = archive.text(named: item.path) else { continue }

            styles.read(text)
        }

        return styles
    }

    mutating func read(_ css: String) {
        // A rule's body is what stands between the brace that opens it and the one that shuts it, and
        // nothing read here nests, so splitting on the braces is enough.
        let stripped = css.replacingOccurrences(
            of: "/\\*[^*]*\\*+(?:[^/*][^*]*\\*+)*/",
            with: " ",
            options: .regularExpression
        )

        for rule in stripped.components(separatedBy: "}") {
            let parts = rule.components(separatedBy: "{")

            guard parts.count == 2 else { continue }

            let names = classNames(in: parts[0])

            guard !names.isEmpty else { continue }

            let body = parts[1].lowercased().replacingOccurrences(of: " ", with: "")

            if body.contains("text-align:center") { centered.formUnion(names) }

            if body.contains("text-align:right") { rightAligned.formUnion(names) }

            if Self.isInset(body) { inset.formUnion(names) }

            if body.contains("font-style:italic") || body.contains("font-style:oblique") {
                italic.formUnion(names)
            }

            if Self.weights.contains(where: { body.contains("font-weight:" + $0) }) { bold.formUnion(names) }

            if body.contains("direction:rtl") { rightToLeft.formUnion(names) }
        }
    }

    /// The classes a selector names, where it is one this reader can match without a whole engine.
    ///
    /// Only a bare class, or a class on an element: anything with a descendant, a child or an
    /// attribute in it depends on where a thing stands rather than on what it is called, and matching
    /// those would mean keeping the document tree the reduction is throwing away.
    private func classNames(in selectors: String) -> Set<String> {
        var names: Set<String> = []

        for selector in selectors.components(separatedBy: ",") {
            let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)

            guard
                !trimmed.isEmpty,
                !trimmed.contains(" "),
                !trimmed.contains(">"),
                !trimmed.contains("["),
                !trimmed.contains(":")
            else { continue }

            let pieces = trimmed.components(separatedBy: ".")

            guard pieces.count == 2, !pieces[1].isEmpty else { continue }

            names.insert(pieces[1].lowercased())
        }

        return names
    }

    /// True where a rule holds its block off both edges, which no ordinary paragraph does.
    ///
    /// Both sides, since one alone is an indent rather than a passage set apart, and a margin of
    /// nothing is the rule saying the block keeps the measure.
    private static func isInset(_ body: String) -> Bool {
        guard
            let left = value(of: "margin-left", in: body),
            let right = value(of: "margin-right", in: body)
        else { return false }

        return left && right
    }

    /// Whether a property is set to something other than nothing.
    private static func value(of property: String, in body: String) -> Bool? {
        guard let found = body.range(of: property + ":") else { return nil }

        let written = body[found.upperBound...].prefix { $0 != ";" && $0 != "}" }
        let figure = written.prefix { $0.isNumber || $0 == "." || $0 == "-" }

        return (Double(figure) ?? 0) > 0
    }

    private static let weights = [ "bold", "bolder", "600", "700", "800", "900" ]
}
