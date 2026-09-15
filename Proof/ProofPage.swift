//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookFormats
import BookKit
import BookRenderer
import SwiftUI
import UIKit

/// The page, with the book's title over it and its number under it, exactly where the reader puts them.
struct ProofPage: View {
    @State private var layout: ChapterLayout?
    @State private var title = ""
    @State private var sheet: CGSize = .zero
    @State private var safeArea = EdgeInsets()

    var body: some View {
        ZStack {
            Self.paper.ignoresSafeArea()

            if let layout, layout.pageCount > 0 {
                let index = min(max(0, Proof.page), layout.pageCount - 1)

                ChapterPageView(layout: layout, pageIndex: index)
                    .ignoresSafeArea()

                head(title, edge: .head)
                head("\(index + 1)", edge: .foot)
            } else {
                Text(verbatim: "…").foregroundStyle(Self.ink)
            }
        }
        // The window rather than the layout, the way the reader reads them: a page reaches past the
        // safe area, so what it is laid out against can only come from the window.
        .onGeometryChange(for: CGSize.self, of: { $0.size }, action: { _ in readWindow() })
        .task(id: sheet) { await build() }
        // The page is the whole picture, as it is in the reader with its controls away.
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    @ViewBuilder
    private func head(_ text: String, edge: RunningHead.Edge) -> some View {
        let size = Proof.fontSize * ChapterLayout.Context.runningHeadScale

        RunningHead(
            text: text,
            edge: edge,
            size: edge == .foot ? size * Self.folio : size,
            ink: Self.ink.opacity(Self.headInk),
            margins: Proof.margins,
            deviceInset: edge == .head ? safeArea.top : safeArea.bottom,
            band: context.runningHeadBand
        )
        .frame(maxHeight: .infinity, alignment: edge == .head ? .top : .bottom)
        .ignoresSafeArea()
    }

    private func readWindow() {
        let scene = UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene

        guard let window = scene?.keyWindow else { return }

        let insets = window.safeAreaInsets
        safeArea = EdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
        sheet = window.bounds.size
    }

    private func build() async {
        guard sheet.width > 1, sheet.height > 1 else { return }

        guard
            let url = Bundle.main.url(forResource: "first-book.fb2", withExtension: "zip"),
            let data = try? Data(contentsOf: url),
            let read = try? await FB2Format().read(data),
            !read.book.sections.isEmpty
        else { return }

        // The longest chapter unless one was asked for: a book's first sections are its front matter,
        // which is set by rules of its own and makes a poor picture of a page.
        let longest = read.book.sections.enumerated().max { $0.element.textLength < $1.element.textLength }
        let at = Proof.chapter.map { min(max(0, $0), read.book.sections.count - 1) } ?? (longest?.offset ?? 0)
        let section = read.book.sections[at]
        let content = await ChapterContent.prepare(html: section.html)

        title = read.book.title
        layout = await ChapterLayout.make(
            chapterId: 1,
            content: content,
            heading: ChapterHeading.make(position: at + 1, title: section.title),
            context: context
        )
    }

    private var context: ChapterLayout.Context {
        ChapterLayout.Context(
            style: ChapterTextStyle(
                face: .serif,
                weight: .regular,
                fontSize: Proof.fontSize,
                lineSpacing: Proof.lineSpacing,
                letterSpacing: 0,
                justifiesRussian: true,
                justifiesEnglish: true,
                textColor: UIColor(Self.ink),
                backgroundColor: UIColor(Self.paper)
            ),
            margins: Proof.margins,
            pageSize: sheet,
            safeArea: safeArea
        )
    }

    /// The reader's own default colours, near enough: what is being looked at is where things stand.
    private static let paper = Color(red: 0.98, green: 0.98, blue: 0.95)
    private static let ink = Color(red: 0.11, green: 0.11, blue: 0.10)
    /// The page number is set a shade smaller than the title, as the reader sets it.
    private static let folio: CGFloat = 0.9
    private static let headInk: CGFloat = 0.6
}

/// What the proof was asked for, which `UserDefaults` reads straight off the launch arguments.
///
/// Read with the coercing accessors: `object(forKey:) as? Double` does not see a `-key value` pair.
private enum Proof {
    static var fontSize: Double { number("proof.fontSize", 19) }
    static var lineSpacing: Double { number("proof.lineSpacing", 7) }
    static var margins: Double { number("proof.margins", 24) }
    static var page: Int { Int(number("proof.page", 1)) }

    /// Nothing where none was asked for, which is what lets the book choose its own chapter.
    static var chapter: Int? {
        let asked = UserDefaults.standard.double(forKey: "proof.chapter")

        return asked == 0 ? nil : Int(asked)
    }

    private static func number(_ key: String, _ fallback: Double) -> Double {
        let asked = UserDefaults.standard.double(forKey: key)

        return asked == 0 ? fallback : asked
    }
}
