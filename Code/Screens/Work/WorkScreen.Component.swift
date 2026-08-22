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
                CoverImage(url: work.coverURL, width: 116, progress: work.readingProgress)

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
            WorkBadges(work: work, showsProgress: true, showsUpdated: true)
                .padding(.top, 4)
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

                libraryButton(model)
            }
        }

        private func libraryButton(_ model: Model) -> some View {
            Button {
                Task { await model.setInLibrary(!model.isInLibrary) }
            } label: {
                Label(
                    model.isInLibrary ? "In your library" : "Add to library",
                    systemImage: model.isInLibrary ? "checkmark" : "plus"
                )
                .font(.subheadline)
                .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.bordered)
            .tint(model.isInLibrary ? .accentColor : .secondary)
            .disabled(model.isUpdatingLibrary)
            .accessibilityIdentifier("work.library")
            .accessibilityHint(
                model.isInLibrary ? "Removes the book from your library" : "Adds the book to your library"
            )
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
