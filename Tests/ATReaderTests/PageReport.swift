//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import UIKit

@testable import ATReader

/// A page taken off a device, at the settings it was read at.
///
/// One unzipped debug report per directory under `Fixtures/Reports`: its `page.txt` and its
/// `settings.txt`. `Scripts/app.sh` names that directory in `TEST_RUNNER_AT_REPORTS` on every run, so a
/// page reported as badly set is checked from then on by dropping the report there. The text is a
/// book's and stays out of this repository, so a fresh checkout has none and every test over them
/// passes having read nothing.
struct PageReport: CustomStringConvertible, Sendable {
    var name: String
    var html: String
    var context: ChapterLayout.Context
    /// The measure the reader had, as the report itself recorded it.
    var textSize: CGSize

    var description: String { name }

    /// Every report to hand, in name order.
    static let all: [PageReport] = {
        guard let root = ProcessInfo.processInfo.environment["AT_REPORTS"] else { return [] }

        let folders = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        return folders.sorted().compactMap { make(root: root, name: $0) }
    }()

    private static func make(root: String, name: String) -> PageReport? {
        let folder = URL(fileURLWithPath: root).appendingPathComponent(name)

        guard
            let page = try? String(contentsOf: folder.appendingPathComponent("page.txt"), encoding: .utf8),
            let settings = try? String(contentsOf: folder.appendingPathComponent("settings.txt"), encoding: .utf8)
        else {
            return nil
        }

        let fields = fields(of: settings)
        let html = page
            .components(separatedBy: "\n")
            .filter { !$0.trimmed.isEmpty }
            .map { "<p>\($0)</p>" }
            .joined()

        guard
            let context = context(from: fields),
            let size = size(fields["textSize"])
        else {
            return nil
        }

        return PageReport(name: name, html: html, context: context, textSize: size)
    }

    private static func fields(of settings: String) -> [String: String] {
        settings.components(separatedBy: "\n").reduce(into: [:]) { result, line in
            guard let colon = line.firstIndex(of: ":") else { return }

            let key = String(line[line.startIndex ..< colon])
            result[key] = String(line[line.index(after: colon)...]).trimmed
        }
    }

    private static func context(from fields: [String: String]) -> ChapterLayout.Context? {
        let face = (fields["face"] ?? "").components(separatedBy: " ")

        guard
            let name = face.first, let typeface = ReaderSettings.Face(rawValue: name),
            let size = size(fields["pageSize"]),
            let insets = insets(fields["safeArea"])
        else {
            return nil
        }

        let style = ChapterTextStyle(
            face: typeface,
            weight: face.count > 1 ? ReaderSettings.Weight(rawValue: face[1]) ?? .regular : .regular,
            fontSize: Double(fields["fontSize"] ?? "") ?? 19,
            lineSpacing: Double(fields["lineSpacing"] ?? "") ?? 0,
            letterSpacing: Double(fields["letterSpacing"] ?? "") ?? 0,
            justifiesRussian: fields["alignment.ru"] == "justified",
            justifiesEnglish: fields["alignment.en"] == "justified",
            textColor: .black
        )

        return ChapterLayout.Context(
            style: style,
            margins: Double(fields["margins"] ?? "") ?? 0,
            pageSize: size,
            safeArea: insets
        )
    }

    /// A size as the report writes it, `440.0 x 956.0`.
    private static func size(_ value: String?) -> CGSize? {
        let parts = (value ?? "").components(separatedBy: "x").compactMap { Double($0.trimmed) }

        guard parts.count == 2 else { return nil }

        return CGSize(width: parts[0], height: parts[1])
    }

    /// The device insets as the report writes them, top first and clockwise.
    private static func insets(_ value: String?) -> EdgeInsets? {
        let parts = (value ?? "").components(separatedBy: ",").compactMap { Double($0.trimmed) }

        guard parts.count == 4 else { return nil }

        return EdgeInsets(top: parts[0], leading: parts[1], bottom: parts[2], trailing: parts[3])
    }

    @MainActor
    func layout() async -> ChapterLayout {
        await ChapterLayout.make(
            chapterId: 1,
            content: await ChapterContent.prepare(html: html),
            heading: ChapterHeading.make(position: 1, title: nil),
            context: context
        )
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
