//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import AuthorTodayBooks
import BookKit
import BookStorage
import DesignSystem
import SwiftUI
import UniformTypeIdentifiers

enum WorkScreen {
    struct Component: View {
        let workId: Int
        let title: String

        @Environment(SessionStore.self)
        private var session

        @Environment(Navigator.self)
        private var navigator

        @Environment(\.dismiss)
        private var dismiss

        @State
        private var isConfirmingDelete = false

        @State
        private var isPickingFile = false

        @State
        private var model: Model?

        @State
        private var isEditingSeries = false

        /// The width the screen was given, which the cover takes its own share of.
        @State
        private var across: CGFloat = 0

        /// How much of the screen the cover stands across. A share rather than a size: a book's page
        /// opens on its cover, and the cover is as large as the screen allows.
        private static let coverShare: CGFloat = 0.3

        var body: some View {
            ScrollView {
                if let model {
                    content(model)
                }
            }
            .background(Design.Surface.screen)
            // No title in the bar: the book names itself under its cover, and the bar would say it twice.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { readButton }

                // Last in the bar, as a menu of everything else always is.
                if model?.isLocal == true {
                    ToolbarItem(placement: .topBarTrailing) { fileMenu }
                }
            }
            .confirmationDialog(
                "Delete this book?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    Task {
                        await model?.deleteLocalBook()
                        dismiss()
                    }
                }
                Button("Keep", role: .cancel) {}
            } message: {
                Text("Its text is on this device only. You would need the file again to read it.")
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                across = $0
            }
            // One file, not several: this replaces one book rather than adding to the shelf.
            .fileImporter(isPresented: $isPickingFile, allowedContentTypes: LocalBookFiles.fileTypes) { result in
                guard case let .success(url) = result else { return }

                Task { await model?.reimport(from: url) }
            }
            .onAppear {
                if model == nil { model = Model(workId: workId, session: session) }
            }
            .task {
                await model?.loadIfNeeded()
                // Reading moves the position and the ring with it, so coming back from the reader
                // redraws from the store.
                await model?.refreshFromStore()
            }
            .overlay {
                if let model, model.isLoading, model.summary == nil {
                    LoadingOverlay(title: "Loading book…", label: "Loading book", background: Design.Surface.screen)
                }
            }
        }

        @ViewBuilder
        private func content(_ model: Model) -> some View {
            VStack(alignment: .leading, spacing: Design.Space.extraLarge) {
                if let summary = model.summary {
                    heading(model, work: summary)
                    actions(model, summary: summary)

                    if let draft = model.seriesDraft { filing(model, draft: draft, work: summary) }
                }

                if let annotation = model.summary?.annotation, !annotation.isEmpty {
                    section("Blurb") {
                        ExpandableText(BookHTML.paragraphs(from: annotation).map(\.text).joined(separator: "\n\n"))
                            .font(Design.Style.item)
                    }
                }

                if !model.tags.isEmpty {
                    section("Tags") { tagCloud(model.tags) }
                }

                if !model.chapters.isEmpty {
                    contentsSection(model)
                }

                if let message = model.errorMessage {
                    Text(message)
                        .font(Design.Style.caption)
                        .foregroundStyle(Design.Palette.alert)
                        .accessibilityLabel("Error: \(message)")
                }
            }
            .padding(Design.Space.extraLarge)
            // Without this the stack is only as wide as its widest loaded child, so the screen starts
            // narrow and visibly snaps outwards once the contents arrive.
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        /// The cover alone across the top, and under it what the book calls itself.
        private func heading(_ model: Model, work: Book) -> some View {
            VStack(spacing: Design.Space.extraLarge) {
                CoverImage(url: work.coverURL, width: across * Self.coverShare, reading: ReadingMark(work))

                VStack(spacing: Design.Space.small) {
                    RowStack {
                        if let number = model.seriesNumber { SeriesNumber(number: number, beside: .title3) }

                        Text(model.shortTitle ?? work.title)
                            .font(Design.Style.title)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(work.authorLine)
                        .font(Design.Style.label)
                        .foregroundStyle(.secondary)

                    statistics(work, costsMoney: model.isLockedByPrice, origin: model.origin)
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: .infinity)
        }

        /// The one thing the page is for, in the bar: a book with nothing to read carries none.
        @ViewBuilder
        private var readButton: some View {
            if let model, let summary = model.summary, let chapterId = model.resumeChapterId {
                Button(summary.hasStartedReading ? "Continue" : "Read") {
                    navigator.present(.reader(.init(workId: model.workId, title: summary.title, chapterId: chapterId)))
                }
                .accessibilityIdentifier("work.read")
                .accessibilityHint("Opens the reader")
            }
        }

        /// What the book is filed under: its series, its volume and where this copy came from. Each
        /// stands at what the app uses now, with what the book itself says under it where the reader
        /// has said otherwise.
        private func filing(_ model: Model, draft: SeriesCorrection.Draft, work: Book) -> some View {
            let standing = SeriesStanding(draft)

            // The volume the shelf gives it where the book states none: a numbering read off the
            // titles of a series is still the volume this book is.
            let volume = standing.volume ?? model.seriesNumber.map { Text($0, format: .number) }

            return card {
                VStack(alignment: .leading, spacing: Design.Space.medium) {
                    fact("Series", standing.series ?? Text("No series"), was: standing.ownSeries)
                    fact("Volume", volume ?? Text("No volume"), was: standing.ownVolume)

                    Button {
                        isEditingSeries = true
                    } label: {
                        Text("Edit")
                            .fontWeight(.medium)
                            .padding(.horizontal, Design.Space.medium)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, Design.Space.small)
                    .accessibilityIdentifier("work.series.edit")
                    .accessibilityHint("Sets the series and volume this book is filed under")
                }
            }
            .sheet(isPresented: $isEditingSeries) {
                SeriesEditor(work: work, writersSeries: model.writersSeries) { edit in
                    Task { await model.setSeries(edit) }
                }
            }
        }

        /// One line of that: what it stands at, and in small under it what the book says where the
        /// reader has overruled it.
        private func fact(_ title: LocalizedStringKey, _ value: Text, was: Text?) -> some View {
            LabeledContent {
                VStack(alignment: .trailing, spacing: Design.Space.nudge) {
                    value

                    if let was {
                        was
                            .font(Design.Style.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } label: {
                Text(title)
                    .foregroundStyle(.secondary)
            }
            .font(Design.Style.item)
            .accessibilityElement(children: .combine)
        }

        private func statistics(_ work: Book, costsMoney: Bool, origin: CoverOrigin) -> some View {
            BookBadges(work: work, showsProgress: true, showsUpdated: true, costsMoney: costsMoney, origin: origin)
                .padding(.top, Design.Space.extraSmall)
        }

        @ViewBuilder
        private func actions(_ model: Model, summary: Book) -> some View {
            if model.resumeChapterId == nil, !model.isLoading {
                Text("No chapters available to read.")
                    .font(Design.Style.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        /// Reading an imported book's file again, for a book that predates something the parser has
        /// since learned. Only imported books have a file to be read again.
        private var fileMenu: some View {
            Menu {
                if let model, model.hasKeptFile {
                    Button {
                        Task { await model.reimportFromKeptFile() }
                    } label: {
                        Label("Re-import", systemImage: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("work.reimport")
                } else {
                    // A book imported before its file was kept has none, so this one asks for it.
                    Button {
                        isPickingFile = true
                    } label: {
                        Label("Re-import…", systemImage: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("work.reimport")
                }

                // An imported book's text is on this device and nowhere else, so taking it off is a
                // deletion rather than clearing a shelf, and it asks first.
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete this book", systemImage: "trash")
                }
                .accessibilityIdentifier("work.delete")
                .accessibilityHint("Removes the book and its text from this device")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Book actions")
        }

        private func tagCloud(_ tags: [String]) -> some View {
            FlowLayout(spacing: Design.Space.medium, lineSpacing: Design.Space.medium) {
                ForEach(tags, id: \.self) { label in
                    Text(label)
                        .font(Design.Style.caption)
                        .padding(.horizontal, Design.Space.medium)
                        .padding(.vertical, Design.Space.small)
                        .background(Design.Surface.fill, in: .capsule)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tags: \(tags.joined(separator: ", "))")
        }

        @ViewBuilder
        private func contentsSection(_ model: Model) -> some View {
            section("Contents") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.chapters) { chapter in
                        chapterRow(model, chapter: chapter)
                    }
                }
            }
        }

        @ViewBuilder
        private func chapterRow(_ model: Model, chapter: BookChapter) -> some View {
            if chapter.isReadable, let summary = model.summary {
                Button {
                    navigator.present(.reader(.init(workId: model.workId, title: summary.title, chapterId: chapter.id)))
                } label: {
                    chapterLabel(chapter, marker: nil, state: model.state(of: chapter))
                }
                .buttonStyle(.plain)

                ForEach(model.bookmarks(inChapter: chapter.id)) { mark in
                    bookmarkRow(model, mark: mark, summary: summary)
                }
            } else {
                // In a book that has to be bought, a chapter is closed because it costs money rather
                // than because it isn't finished. The ones without a mark are the free ones.
                chapterLabel(chapter, marker: model.isLockedByPrice ? .paid : .locked)
            }
        }

        /// A mark under its chapter, which opens the book where it stands.
        private func bookmarkRow(_ model: Model, mark: Bookmark, summary: Book) -> some View {
            Button {
                navigator.present(.reader(.init(workId: model.workId, title: summary.title, chapterId: mark.chapterId)))
            } label: {
                BookmarkLabel(share: mark.share(ofChapterLength: chapterLength(model, of: mark.chapterId)))
                    .padding(.vertical, Design.Space.small)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the book here")
            .contextMenu {
                Button("Remove bookmark", systemImage: "bookmark.slash", role: .destructive) {
                    model.remove(bookmark: mark)
                }
            }
        }

        private func chapterLength(_ model: Model, of id: Int) -> Int? {
            model.chapters.first { $0.id == id }?.textLength
        }

        private enum ChapterMarker {
            case paid
            case locked

            var systemImage: String {
                switch self {
                    case .paid: "dollarsign"
                    case .locked: "lock.fill"
                }
            }
        }

        /// A chapter, with how far the reader got through it standing where a list's bullet would, on
        /// the first line of its title.
        private func chapterLabel(
            _ chapter: BookChapter,
            marker: ChapterMarker?,
            state: Model.ChapterState = .unread
        ) -> some View {
            RowStack(spacing: Design.Space.medium) {
                Group {
                    if let marker {
                        LineGlyph(systemImage: marker.systemImage)
                            .font(Design.Style.caption)
                            .foregroundStyle(
                                marker == .paid ? AnyShapeStyle(Design.Palette.caution) : AnyShapeStyle(.tertiary)
                            )
                    } else {
                        ProgressMark(progress: state.progress, isComplete: state == .read)
                            .centredOnCapitals(of: .callout)
                    }
                }
                .frame(width: Design.Size.mark)

                Text(chapter.displayTitle)
                    .font(Design.Style.item)
                    .foregroundStyle(marker == nil ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Design.Space.small)
            .contentShape(.rect)
            .accessibilityLabel(label(chapter, marker: marker, state: state))
        }

        private func label(_ chapter: BookChapter, marker: ChapterMarker?, state: Model.ChapterState) -> String {
            switch marker {
                case .paid: return String(localized: "\(chapter.displayTitle), paid")
                case .locked: return String(localized: "\(chapter.displayTitle), locked")
                case .none: break
            }

            switch state {
                case .unread: return chapter.displayTitle
                case .read: return String(localized: "\(chapter.displayTitle), read")
                case let .reading(progress):
                    let percent = BookFormatting.progress(progress) ?? ""
                    return String(localized: "\(chapter.displayTitle), \(percent) read")
            }
        }

        private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
            card {
                VStack(alignment: .leading, spacing: Design.Space.medium) {
                    Text(title)
                        .font(Design.Style.heading)

                    content()
                }
            }
        }

        /// The ground every block on this page stands on.
        private func card(@ViewBuilder content: () -> some View) -> some View {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Design.Space.large)
                .background(Design.Surface.card, in: .rect(cornerRadius: Design.Radius.medium))
        }
    }

    /// A chapter's own progress: a tick once it has been read, a ring filled as far as the reader got,
}
