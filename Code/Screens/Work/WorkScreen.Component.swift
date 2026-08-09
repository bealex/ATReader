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

        @State
        private var model: Model?

        @State
        private var isShowingContents = false

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
            .task { await model?.loadIfNeeded() }
            .overlay {
                if let model, model.isLoading, model.details == nil {
                    ProgressView("Loading book…")
                        .accessibilityLabel("Loading book")
                }
            }
        }

        @ViewBuilder
        private func content(_ model: Model) -> some View {
            VStack(alignment: .leading, spacing: 20) {
                if let summary = model.summary {
                    heading(summary)
                    actions(model, summary: summary)
                }

                if let annotation = model.details?.annotation, !annotation.isEmpty {
                    section("Blurb") {
                        Text(ChapterHTML.paragraphs(from: annotation).map(\.text).joined(separator: "\n\n"))
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
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

        private func heading(_ work: WorkSummary) -> some View {
            HStack(alignment: .top, spacing: 16) {
                CoverImage(url: work.coverURL, width: 116)

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

                    statistics(work)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
        }

        private func statistics(_ work: WorkSummary) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    if let length = WorkFormatting.length(work.textLength) {
                        Label(length, systemImage: "doc.text")
                    }

                    if let likes = WorkFormatting.likes(work.likeCount) {
                        Label(likes, systemImage: "heart")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Label(
                    work.isOngoing ? "Still being written" : "Finished",
                    systemImage: work.isOngoing ? "pencil.circle" : "checkmark.seal"
                )
                .font(.caption)
                .foregroundStyle(work.isOngoing ? .orange : .green)
            }
            .padding(.top, 2)
        }

        @ViewBuilder
        private func actions(_ model: Model, summary: WorkSummary) -> some View {
            VStack(spacing: 10) {
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

                if let progress = summary.readingProgress, progress > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress)
                            .tint(.accentColor)

                        Text("\(WorkFormatting.progress(progress) ?? "") read")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(WorkFormatting.progress(progress) ?? "") read")
                }

                shelfPicker(model)
            }
        }

        private func shelfPicker(_ model: Model) -> some View {
            HStack(spacing: 8) {
                ForEach(LibraryState.shelves, id: \.self) { state in
                    Button(
                        action: { Task { await model.setLibraryState(state) } },
                        label: {
                            Label(state.title, systemImage: state.systemImage)
                                .font(.caption)
                                .frame(maxWidth: .infinity, minHeight: 26)
                        }
                    )
                    .buttonStyle(.bordered)
                    .tint(model.libraryState == state ? .accentColor : .secondary)
                    .disabled(model.isUpdatingLibrary)
                    .accessibilityLabel(state.title)
                    .accessibilityAddTraits(model.libraryState == state ? [ .isSelected ] : [])
                    .accessibilityHint("Changes the shelf in your library")
                }
            }
        }

        private func tagCloud(_ tags: [String]) -> some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tags, id: \.self) { label in
                        Text(label)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(.tertiarySystemFill), in: .capsule)
                    }
                }
            }
            .accessibilityLabel("Tags: \(tags.joined(separator: ", "))")
        }

        @ViewBuilder
        private func contentsSection(_ model: Model) -> some View {
            section("Contents") {
                VStack(alignment: .leading, spacing: 0) {
                    let visible = isShowingContents ? model.chapters : Array(model.chapters.prefix(5))

                    ForEach(visible) { chapter in
                        chapterRow(model, chapter: chapter)

                        if chapter.id != visible.last?.id {
                            Divider()
                        }
                    }

                    if model.chapters.count > 5 {
                        Button(isShowingContents ? "Collapse" : "Show all \(model.chapters.count) chapters") {
                            withAnimation { isShowingContents.toggle() }
                        }
                        .font(.footnote)
                        .padding(.top, 10)
                        .accessibilityHint("Expands the chapter list")
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
                    chapterLabel(chapter, isLocked: false)
                }
                .buttonStyle(.plain)
            } else {
                chapterLabel(chapter, isLocked: true)
            }
        }

        private func chapterLabel(_ chapter: ChapterInfo, isLocked: Bool) -> some View {
            HStack {
                Text(chapter.displayTitle)
                    .font(.callout)
                    .foregroundStyle(isLocked ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 9)
            .contentShape(.rect)
            .accessibilityLabel(isLocked ? "\(chapter.displayTitle), locked" : chapter.displayTitle)
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
}
