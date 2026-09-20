//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import SwiftUI

/// A place in a book: a chapter, and how far into its own text, counted the way a reading position is.
public struct BookPosition: Equatable, Hashable, Sendable {
    public let chapterId: Int
    public let offset: Int

    public init(chapterId: Int, offset: Int) {
        self.chapterId = chapterId
        self.offset = offset
    }

    /// What the book's own title page is kept as, being the one page with no text behind it. An offset
    /// is never negative otherwise, and kept as nought a book closed on its title page would reopen on
    /// the page after it.
    public static let titleOffset = -1
}

/// One page of a book as it stands on screen.
public struct BookPage: Identifiable, Equatable {
    /// One chapter's share of a page. A page carries two where a chapter runs on from the page the one
    /// before it ended on, and each draws only its own lines in its own place.
    public struct Piece: Identifiable, Equatable {
        public let layout: ChapterLayout
        public let page: ChapterLayout.Page

        public var id: String { "\(layout.chapterId).\(page.lines.lowerBound)" }

        public static func == (lhs: Piece, rhs: Piece) -> Bool {
            lhs.layout === rhs.layout && lhs.page == rhs.page
        }
    }

    public enum Content: Equatable {
        /// The book's own title page, in front of its first chapter.
        case title
        case text([Piece])
        /// A chapter whose text is not on the device and could not be fetched.
        case missing
    }

    public let content: Content
    /// Where the page begins, which is what a reading position keeps.
    public let start: BookPosition
    /// Where the page stops, which is how far into the book a reader on it has got.
    public let end: BookPosition

    public var id: String { "\(start.chapterId).\(start.offset)-\(end.chapterId).\(end.offset)" }

    public var pieces: [Piece] {
        guard case let .text(pieces) = content else { return [] }

        return pieces
    }

    public var isTitle: Bool { content == .title }

    public var isText: Bool { !pieces.isEmpty }
}

/// A book cut into pages around wherever the reader is, for one style and one page size.
///
/// Nothing is measured ahead of the reader. A page is cut from the one beside it, forwards from where
/// that one stopped or backwards from where it began, so opening a book costs its first page, and a
/// change of size throws away the few pages around the reader and nothing else.
@MainActor
public final class BookLayout {
    /// One chapter as the book lays it out.
    public struct Chapter: Equatable, Sendable {
        public let id: Int
        public let heading: ChapterHeading
        /// Among the book's own top divisions, each of which opens a page of its own. Running one on
        /// reads it as a continuation of what came before, which is what a part or a book is not.
        public let opensItsOwnPage: Bool

        public init(id: Int, heading: ChapterHeading, opensItsOwnPage: Bool) {
            self.id = id
            self.heading = heading
            self.opensItsOwnPage = opensItsOwnPage
        }
    }

    /// A chapter's parsed text, or `nil` where the device doesn't have it and can't get it.
    public typealias ContentProvider = @MainActor (Int) async -> ChapterContent?

    /// How much of a chapter has to reach the page it shares for it to run on at all. A heading with
    /// one or two lines under it reads as a title stranded at the foot of the page.
    public static let runOnLineMinimum = 3

    public let context: ChapterLayout.Context

    private let chapters: [Chapter]
    private let places: [Int: Int]
    private let content: ContentProvider
    private var layouts: [Int: ChapterLayout] = [:]
    private var making: [Int: Task<ChapterLayout?, Never>] = [:]

    public init(chapters: [Chapter], context: ChapterLayout.Context, content: @escaping ContentProvider) {
        self.chapters = chapters
        self.context = context
        self.content = content
        self.places = Dictionary(chapters.enumerated().map { ($1.id, $0) }) { first, _ in first }
    }

    // MARK: - Chapters

    /// A chapter set as text, reading its text first where it hasn't been.
    public func layout(of chapterId: Int) async -> ChapterLayout? {
        if let made = layouts[chapterId] { return made }
        if let running = making[chapterId] { return await running.value }
        guard let chapter = places[chapterId].map({ chapters[$0] }) else { return nil }

        let context = context
        let content = content
        let task = Task { () -> ChapterLayout? in
            guard let text = await content(chapterId) else { return nil }

            return await ChapterLayout.prepare(
                chapterId: chapterId,
                content: text,
                heading: chapter.heading,
                context: context
            )
        }

        making[chapterId] = task

        let made = await task.value

        making[chapterId] = nil

        if let made, layouts[chapterId] == nil { layouts[chapterId] = made }

        return layouts[chapterId] ?? made
    }

    /// A chapter already set as text, without reading anything to get it.
    public func loadedLayout(of chapterId: Int) -> ChapterLayout? { layouts[chapterId] }

    /// Lets go of every chapter but these. A page on screen holds on to the chapter it shows anyway.
    public func keep(only chapterIds: Set<Int>) {
        layouts = layouts.filter { chapterIds.contains($0.key) }
    }

    // MARK: - Pages

    /// The page a position stands on: the title page, or the page that starts on the line the position
    /// falls in. A position at the very end of a chapter stands on its last page.
    public func page(at position: BookPosition) async -> BookPage? {
        guard let index = places[position.chapterId] else { return chapters.isEmpty ? nil : title }

        if position.offset < 0 { return index == 0 ? title : await opening(at: index) }

        guard let layout = await layout(of: chapters[index].id) else { return missing(index) }

        if layout.isEmpty {
            if let next = await opening(at: index + 1) { return next }

            return await closing(before: index)
        }

        if position.offset >= layout.sourceLength, let end = await layout.closingLine() {
            return await emptying(layout, at: index, to: end)
        }

        guard let line = await layout.line(at: position.offset) else { return await opening(at: index) }

        return await filling(layout, at: index, from: line)
    }

    /// The page that follows a page, or `nil` at the end of the book.
    public func page(after page: BookPage) async -> BookPage? {
        guard let index = places[page.end.chapterId] else { return nil }

        switch page.content {
            case .title:
                return await opening(at: 0)
            case .missing:
                return await opening(at: index + 1)
            case let .text(pieces):
                guard let last = pieces.last else { return nil }
                guard
                    last.layout.ends(last.page)
                else {
                    return await filling(last.layout, at: index, from: last.page.lines.upperBound)
                }

                return await opening(at: index + 1)
        }
    }

    /// The page that comes before a page, or `nil` at the front of the book.
    public func page(before page: BookPage) async -> BookPage? {
        guard let index = places[page.start.chapterId] else { return nil }

        switch page.content {
            case .title:
                return nil
            case .missing:
                return await closing(before: index)
            case let .text(pieces):
                guard let first = pieces.first else { return nil }
                guard
                    first.layout.opens(first.page)
                else {
                    return await emptying(first.layout, at: index, to: first.page.lines.lowerBound)
                }

                return await closing(before: index)
        }
    }

    /// Where a place in a chapter stands when the chapter is cut from its own beginning: the first
    /// character of the page that holds it, and which of that page's lines it falls on.
    public struct PagePlace: Equatable, Sendable {
        public let start: Int
        public let line: Int
    }

    /// Where each of these places in one chapter stands, cutting forwards from the chapter's opening.
    ///
    /// The only way to learn which page holds a place, pages being cut from the one beside them. A page
    /// the reader is handed may open with the end of the chapter before, and the opening this answers
    /// with cuts that same page again.
    public func pagePlaces(of positions: [Int], in chapterId: Int) async -> [Int: PagePlace] {
        guard !positions.isEmpty, let layout = await layout(of: chapterId) else { return [:] }
        guard var line = await layout.openingLine() else { return [:] }

        var wanted = Set(positions)
        var found: [Int: PagePlace] = [:]

        while !wanted.isEmpty {
            let page = await layout.page(from: line, top: 0, opens: line == layout.firstLine)
            let start = layout.startOffset(of: page)
            let end = max(layout.endOffset(of: page), start + 1)

            for position in wanted where position >= start && position < end {
                let at = layout.line(atPosition: position, on: page)?.index ?? page.lines.lowerBound

                found[position] = PagePlace(start: start, line: at - page.lines.lowerBound)
                wanted.remove(position)
            }

            if layout.ends(page) { break }

            line = page.lines.upperBound
        }

        return found
    }

    /// True where nothing can follow a page: it carries the end of the book's last chapter.
    public func isLast(_ page: BookPage) -> Bool {
        guard let index = places[page.end.chapterId] else { return true }
        guard index == chapters.count - 1 else { return false }

        return page.pieces.last.map { $0.layout.ends($0.page) } ?? !page.isTitle
    }

    private var title: BookPage? {
        guard let first = chapters.first else { return nil }

        let position = BookPosition(chapterId: first.id, offset: BookPosition.titleOffset)

        return BookPage(content: .title, start: position, end: position)
    }

    private func missing(_ index: Int) -> BookPage {
        let position = BookPosition(chapterId: chapters[index].id, offset: 0)

        return BookPage(content: .missing, start: position, end: position)
    }

    /// The first page of the first chapter from `index` on with anything in it.
    private func opening(at index: Int) async -> BookPage? {
        var at = index

        while chapters.indices.contains(at) {
            guard let layout = await layout(of: chapters[at].id) else { return missing(at) }

            if let first = await layout.openingLine() { return await filling(layout, at: at, from: first) }

            at += 1
        }

        return nil
    }

    /// The last page of the last chapter before `index` with anything in it, or the title page.
    private func closing(before index: Int) async -> BookPage? {
        var at = index - 1

        while at >= 0 {
            guard let layout = await layout(of: chapters[at].id) else { return missing(at) }

            if let end = await layout.closingLine() { return await emptying(layout, at: at, to: end) }

            at -= 1
        }

        return title
    }

    /// The page that starts on a line, with every chapter that runs on under the end of the one before.
    private func filling(_ layout: ChapterLayout, at index: Int, from start: Int) async -> BookPage {
        layouts[layout.chapterId] = layout

        var pieces = [
            BookPage.Piece(
                layout: layout,
                page: await layout.page(from: start, top: 0, opens: start == layout.firstLine)
            )
        ]
        var at = index

        while let last = pieces.last, last.layout.ends(last.page), let head = await runningOn(after: last, at: at) {
            pieces.append(head)
            at += 1
        }

        return text(pieces)
    }

    /// The opening of the chapter after `index`, set under the end of the one before it where it may run
    /// on and brings enough of itself onto the page.
    private func runningOn(after piece: BookPage.Piece, at index: Int) async -> BookPage.Piece? {
        let next = index + 1
        let top = piece.layout.bottom(of: piece.page) + chapterGap

        guard
            chapters.indices.contains(next),
            !chapters[next].opensItsOwnPage,
            context.textSize.height - top >= runOnRoom,
            let layout = await layout(of: chapters[next].id),
            let first = await layout.openingLine()
        else { return nil }

        let head = await layout.page(from: first, top: top, opens: false)

        guard layout.bodyLineCount(on: head) >= Self.runOnLineMinimum else { return nil }

        layouts[layout.chapterId] = layout
        return BookPage.Piece(layout: layout, page: head)
    }

    /// The page that ends just before a line, with the end of every chapter above whose opening it
    /// shares the page with.
    ///
    /// A chapter's opening cut from behind stands on a page of its own, at the foot of it where it is
    /// short. Where the chapter may run on, the end of the chapter before takes the room above instead,
    /// as it would have read forwards.
    private func emptying(_ layout: ChapterLayout, at index: Int, to limit: Int) async -> BookPage {
        layouts[layout.chapterId] = layout

        var pieces = [
            BookPage.Piece(
                layout: layout,
                page: await layout.page(to: limit, room: context.textSize.height, opens: true)
            )
        ]
        var at = index

        while let tail = await runningOn(before: pieces, at: at) {
            pieces.insert(tail, at: 0)
            at -= 1
        }

        return text(stacked(pieces))
    }

    /// The end of the chapter before `index`, to stand above the pieces its opening begins.
    private func runningOn(before pieces: [BookPage.Piece], at index: Int) async -> BookPage.Piece? {
        guard
            let head = pieces.first,
            head.layout.opens(head.page),
            index > 0,
            !chapters[index].opensItsOwnPage,
            head.layout.bodyLineCount(on: head.page) >= Self.runOnLineMinimum
        else { return nil }

        let room = context.textSize.height - height(of: pieces) - chapterGap

        guard
            room >= runOnRoom,
            let layout = await layout(of: chapters[index - 1].id),
            let end = await layout.closingLine()
        else { return nil }

        layouts[layout.chapterId] = layout
        return BookPage.Piece(layout: layout, page: await layout.page(to: end, room: room, opens: true))
    }

    /// How deep a stack of pieces stands, each at its own spacing with the gap between chapters.
    private func height(of pieces: [BookPage.Piece]) -> CGFloat {
        pieces.reduce(CGFloat(0)) { total, piece in
            total + piece.layout.bottom(of: piece.layout.moved(piece.page, to: 0))
        } + CGFloat(max(0, pieces.count - 1)) * chapterGap
    }

    /// The pieces of one page set one under another, the last at the foot where the page after goes on
    /// with it.
    private func stacked(_ pieces: [BookPage.Piece]) -> [BookPage.Piece] {
        guard pieces.count > 1 else { return pieces }

        var result = [ pieces[0] ]
        var bottom = pieces[0].layout.bottom(of: pieces[0].page)

        for (place, piece) in pieces.enumerated().dropFirst() {
            let layout = piece.layout
            var page = layout.moved(piece.page, to: bottom + chapterGap)

            if place == pieces.count - 1, !layout.ends(page) {
                page = layout.moved(
                    piece.page,
                    to: context.textSize.height - layout.bottom(of: layout.moved(page, to: 0))
                )
            }

            result.append(BookPage.Piece(layout: layout, page: page))
            bottom = layout.bottom(of: page)
        }

        return result
    }

    private func text(_ pieces: [BookPage.Piece]) -> BookPage {
        let first = pieces[0]
        let last = pieces[pieces.count - 1]

        return BookPage(
            content: .text(pieces),
            start: BookPosition(chapterId: first.layout.chapterId, offset: first.layout.startOffset(of: first.page)),
            end: BookPosition(chapterId: last.layout.chapterId, offset: last.layout.endOffset(of: last.page))
        )
    }

    /// The air between the end of one chapter and the opening of the next on a page they share.
    private var chapterGap: CGFloat { context.style.fontSize * 2.5 }

    /// The least room a chapter may run on into: six lines, or a quarter of the page.
    private var runOnRoom: CGFloat {
        let style = context.style

        return max((style.fontSize + style.lineSpacing) * 6, context.textSize.height * 0.25)
    }
}
