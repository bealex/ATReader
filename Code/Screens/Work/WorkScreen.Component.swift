//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import SwiftUI

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
        private var model: Model?

        var body: some View {
            ScrollView {
                if let model {
                    content(model)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
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
                    LoadingOverlay(
                        title: "Loading book…",
                        label: "Loading book",
                        background: Color(.systemGroupedBackground)
                    )
                }
            }
        }

        @ViewBuilder
        private func content(_ model: Model) -> some View {
            VStack(alignment: .leading, spacing: 20) {
                if let summary = model.summary {
                    heading(model, work: summary)
                    actions(model, summary: summary)
                }

                if let annotation = model.summary?.annotation, !annotation.isEmpty {
                    section("Blurb") {
                        ExpandableText(ChapterHTML.paragraphs(from: annotation).map(\.text).joined(separator: "\n\n"))
                            .font(.callout)
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
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Error: \(message)")
                }
            }
            .padding(16)
            // Without this the stack is only as wide as its widest loaded child, so the screen starts
            // narrow and visibly snaps outwards once the contents arrive.
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func heading(_ model: Model, work: WorkSummary) -> some View {
            HStack(alignment: .top, spacing: 16) {
                CoverImage(url: work.coverURL, width: 116, progress: work.readingProgress)
                    .overlay(alignment: .topTrailing) {
                        // A book from a file is on no service shelf, so it carries no shelf mark.
                        if !model.isLocal { libraryMark(model) }
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text(work.title)
                        .font(.title3.bold())
                        .fixedSize(horizontal: false, vertical: true)

                    Text(work.authorLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let series = work.seriesTitle, !series.isEmpty {
                        Text("Series: \(series)")
                            .font(.caption)
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
                    .padding(4)
            }
            .buttonStyle(.plain)
            .disabled(model.isUpdatingLibrary)
            .accessibilityIdentifier("work.library")
            .accessibilityLabel(model.isInLibrary ? "In your library" : "Add to library")
            .accessibilityHint(
                model.isInLibrary ? "Removes the book from your library" : "Adds the book to your library"
            )
        }

        private func statistics(_ work: WorkSummary, costsMoney: Bool) -> some View {
            WorkBadges(work: work, showsProgress: true, showsUpdated: true, costsMoney: costsMoney)
                .padding(.top, 4)
        }

        @ViewBuilder
        private func actions(_ model: Model, summary: WorkSummary) -> some View {
            if let chapterId = model.resumeChapterId {
                NavigationLink(
                    value: AppRoute.reader(.init(workId: model.workId, title: summary.title, chapterId: chapterId))
                ) {
                    Label(summary.hasStartedReading ? "Continue reading" : "Read", systemImage: "book.fill")
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("work.read")
                .accessibilityHint("Opens the reader")
            } else if !model.isLoading {
                Text("No chapters available to read.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if model.isLocal { deleteButton(model) }
        }

        /// An imported book's text is on this device and nowhere else, so taking it off is a deletion
        /// rather than clearing a shelf, and it asks first.
        private func deleteButton(_ model: Model) -> some View {
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete this book", systemImage: "trash")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.bordered)
            .padding(.top, 10)
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
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(tags, id: \.self) { label in
                    Text(label)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(.tertiarySystemFill), in: .capsule)
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
        private func chapterRow(_ model: Model, chapter: ChapterInfo) -> some View {
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
            _ chapter: ChapterInfo,
            marker: ChapterMarker?,
            state: Model.ChapterState = .unread
        ) -> some View {
            HStack {
                Text(chapter.displayTitle)
                    .font(.callout)
                    .foregroundStyle(marker == nil ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let marker {
                    Image(systemName: marker.systemImage)
                        .font(.caption)
                        .foregroundStyle(marker == .paid ? AnyShapeStyle(Color.indigo) : AnyShapeStyle(.tertiary))
                        .accessibilityHidden(true)
                } else {
                    ChapterMark(state: state)
                }
            }
            .padding(.vertical, 9)
            .contentShape(.rect)
            .accessibilityLabel(label(chapter, marker: marker, state: state))
        }

        private func label(_ chapter: ChapterInfo, marker: ChapterMarker?, state: Model.ChapterState) -> String {
            switch marker {
                case .paid: return String(localized: "\(chapter.displayTitle), paid")
                case .locked: return String(localized: "\(chapter.displayTitle), locked")
                case .none: break
            }

            switch state {
                case .unread: return chapter.displayTitle
                case .read: return String(localized: "\(chapter.displayTitle), read")
                case let .reading(progress):
                    let percent = WorkFormatting.progress(progress) ?? ""
                    return String(localized: "\(chapter.displayTitle), \(percent) read")
            }
        }

        @ViewBuilder
        private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)

                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
    }

    /// A chapter's own progress: a tick once it has been read, a ring filled as far as the reader got,
    /// and an outline for one they have not opened.
    struct ChapterMark: View {
        let state: Model.ChapterState

        private static let size: CGFloat = 16
        private static let lineWidth: CGFloat = 2

        var body: some View {
            ZStack {
                switch state {
                    case .unread:
                        track
                    case let .reading(progress):
                        track

                        Circle()
                            .trim(from: 0, to: max(0.04, min(1, progress)))
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                            .padding(Self.lineWidth / 2)
                            .rotationEffect(.degrees(-90))
                    case .read:
                        Circle()
                            .fill(Color.accentColor)

                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                }
            }
            .frame(width: Self.size, height: Self.size)
            .accessibilityHidden(true)
        }

        private var track: some View {
            Circle()
                .stroke(Color.primary.opacity(0.15), lineWidth: Self.lineWidth)
                .padding(Self.lineWidth / 2)
        }
    }
}
