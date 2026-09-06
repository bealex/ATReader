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

        @Environment(\.dismiss)
        private var dismiss

        @State
        private var isConfirmingDelete = false

        @State
        private var isPickingFile = false

        @State
        private var model: Model?

        var body: some View {
            ScrollView {
                if let model {
                    content(model)
                }
            }
            .background(Design.Surface.screen)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                if model?.isLocal == true {
                    ToolbarItem(placement: .topBarTrailing) { fileMenu }
                }
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

        private func heading(_ model: Model, work: Book) -> some View {
            HStack(alignment: .top, spacing: Design.Space.extraLarge) {
                CoverImage(
                    url: work.coverURL,
                    width: Design.Size.coverLarge,
                    progress: work.readingProgress,
                    isLocal: model.isLocal
                )
                .overlay(alignment: .topTrailing) {
                    // A book from a file is on no service shelf, so it carries no shelf mark.
                    if !model.isLocal { libraryMark(model) }
                }

                VStack(alignment: .leading, spacing: Design.Space.small) {
                    Text(work.title)
                        .font(Design.Style.title)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(work.authorLine)
                        .font(Design.Style.label)
                        .foregroundStyle(.secondary)

                    if let series = work.seriesTitle, !series.isEmpty {
                        Text("Series: \(series)")
                            .font(Design.Style.caption)
                            .foregroundStyle(.tertiary)
                    }

                    statistics(work, costsMoney: model.isLockedByPrice)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }

        private func libraryMark(_ model: Model) -> some View {
            Button {
                Task { await model.setInLibrary(!model.isInLibrary) }
            } label: {
                LibraryMark(inLibrary: model.isInLibrary)
                    .padding(Design.Space.extraSmall)
            }
            .buttonStyle(.plain)
            .disabled(model.isUpdatingLibrary)
            .accessibilityIdentifier("work.library")
            .accessibilityLabel(model.isInLibrary ? "In your library" : "Add to library")
            .accessibilityHint(
                model.isInLibrary ? "Removes the book from your library" : "Adds the book to your library"
            )
        }

        private func statistics(_ work: Book, costsMoney: Bool) -> some View {
            WorkBadges(work: work, showsProgress: true, showsUpdated: true, costsMoney: costsMoney)
                .padding(.top, Design.Space.extraSmall)
        }

        @ViewBuilder
        private func actions(_ model: Model, summary: Book) -> some View {
            if let chapterId = model.resumeChapterId {
                NavigationLink(
                    value: AppRoute.reader(.init(workId: model.workId, title: summary.title, chapterId: chapterId))
                ) {
                    Label(summary.hasStartedReading ? "Continue reading" : "Read", systemImage: "book.fill")
                        .actionLabel()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("work.read")
                .accessibilityHint("Opens the reader")
            } else if !model.isLoading {
                Text("No chapters available to read.")
                    .font(Design.Style.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if model.isLocal { deleteButton(model) }
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
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Book actions")
            .accessibilityHint("Reads this book’s file again, keeping your place")
        }

        /// An imported book's text is on this device and nowhere else, so taking it off is a deletion
        /// rather than clearing a shelf, and it asks first.
        private func deleteButton(_ model: Model) -> some View {
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete this book", systemImage: "trash")
                    .actionLabel()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, Design.Space.medium)
            .accessibilityIdentifier("work.delete")
            .accessibilityHint("Removes the book and its text from this device")
            .confirmationDialog(
                "Delete this book?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    Task {
                        await model.deleteLocalBook()
                        dismiss()
                    }
                }
                Button("Keep", role: .cancel) {}
            } message: {
                Text("Its text is on this device only. You would need the file again to read it.")
            }
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

                        if chapter.id != model.chapters.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }

        @ViewBuilder
        private func chapterRow(_ model: Model, chapter: BookChapter) -> some View {
            if chapter.isReadable, let summary = model.summary {
                NavigationLink(
                    value: AppRoute.reader(.init(workId: model.workId, title: summary.title, chapterId: chapter.id))
                ) {
                    chapterLabel(chapter, marker: nil, state: model.state(of: chapter))
                }
                .buttonStyle(.plain)
            } else {
                // In a book that has to be bought, a chapter is closed because it costs money rather
                // than because it isn't finished. The ones without a mark are the free ones.
                chapterLabel(chapter, marker: model.isLockedByPrice ? .paid : .locked)
            }
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

        private func chapterLabel(
            _ chapter: BookChapter,
            marker: ChapterMarker?,
            state: Model.ChapterState = .unread
        ) -> some View {
            HStack {
                Text(chapter.displayTitle)
                    .font(Design.Style.item)
                    .foregroundStyle(marker == nil ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let marker {
                    Image(systemName: marker.systemImage)
                        .font(Design.Style.caption)
                        .foregroundStyle(
                            marker == .paid ? AnyShapeStyle(Design.Palette.caution) : AnyShapeStyle(.tertiary)
                        )
                        .accessibilityHidden(true)
                } else {
                    ProgressRing(
                        progress: state.progress,
                        isComplete: state == .read,
                        // A chapter just begun still reads as begun.
                        minimumTrim: 0.04
                    )
                }
            }
            .padding(.vertical, Design.Space.medium)
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

        @ViewBuilder
        private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
            VStack(alignment: .leading, spacing: Design.Space.medium) {
                Text(title)
                    .font(Design.Style.heading)

                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Design.Space.large)
            .background(Design.Surface.card, in: .rect(cornerRadius: Design.Radius.medium))
        }
    }

    /// A chapter's own progress: a tick once it has been read, a ring filled as far as the reader got,
}
