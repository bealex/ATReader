//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import SwiftUI

enum ReaderScreen {
    struct Component: View {
        let workId: Int
        let title: String
        let initialChapterId: Int?

        @Environment(SessionStore.self)
        private var session

        @Environment(ReaderSettings.self)
        private var settings

        @State
        private var model: Model?

        @State
        private var isShowingSettings = false

        @State
        private var isShowingContents = false

        @State
        private var pageSize: CGSize = .zero

        var body: some View {
            Group {
                if let model {
                    page(model)
                } else {
                    Color.clear
                }
            }
            .background(settings.theme.background.ignoresSafeArea())
            .navigationTitle(model?.chapterTitle ?? title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .backSwipeDisabled()
            .toolbar { toolbar }
            .toolbarBackground(settings.theme.background, for: .navigationBar)
            .preferredColorScheme(settings.theme.colorScheme)
            .sheet(isPresented: $isShowingSettings) { SettingsSheet() }
            .sheet(isPresented: $isShowingContents) {
                if let model {
                    ContentsSheet(model: model, isPresented: $isShowingContents)
                }
            }
            .onAppear {
                if model == nil {
                    model = Model(
                        workId: workId,
                        workTitle: title,
                        initialChapterId: initialChapterId,
                        session: session
                    )
                }
            }
            .task { await model?.loadIfNeeded() }
        }

        @ViewBuilder
        private func page(_ model: Model) -> some View {
            @Bindable var model = model

            VStack(spacing: 0) {
                pageArea($model)

                if let caption = model.pageCaption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(settings.theme.foreground.opacity(0.45))
                        .padding(.bottom, 6)
                        .accessibilityIdentifier("reader.caption")
                        .accessibilityLabel(caption)
                }
            }
            .overlay {
                if model.isLoading && model.paragraphs.isEmpty {
                    ProgressView("Loading chapter…")
                        .accessibilityLabel("Loading chapter")
                } else if let message = model.errorMessage, model.paragraphs.isEmpty {
                    ContentUnavailableView("Couldn’t open", systemImage: "book.closed", description: Text(message))
                }
            }
        }

        @ViewBuilder
        private func pageArea(_ model: Bindable<Model>) -> some View {
            let value = model.wrappedValue

            PageTurnView(
                pageCount: value.pageCount,
                index: model.currentPage,
                onPastEnd: { Task { await value.goToNextChapter() } },
                onPastStart: { Task { await value.goToPreviousChapter() } },
                page: { index in
                    if value.pageRanges.indices.contains(index) {
                        ChapterPageView(
                            text: value.attributedText,
                            range: value.pageRanges[index],
                            margins: settings.margins
                        )
                        .background(settings.theme.background)
                    } else {
                        settings.theme.background
                    }
                }
            )
            .accessibilityIdentifier("reader.page")
            .onGeometryChange(for: CGSize.self, of: { $0.size }, action: { pageSize = $0 })
            .onChange(of: pageSize) { relayout(value) }
            .onChange(of: settings.textStyle) { relayout(value) }
            .onChange(of: settings.margins) { relayout(value) }
            .onChange(of: value.layoutRevision) { relayout(value) }
        }

        /// Re-paginates for the current page size and style. Cheap when nothing relevant changed — the
        /// model short-circuits on an unchanged style and size.
        private func relayout(_ model: Model) {
            model.layout(
                style: settings.textStyle,
                textSize: ChapterPagination.textSize(in: pageSize, margins: settings.margins)
            )
        }

        @ToolbarContentBuilder
        private var toolbar: some ToolbarContent {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Contents", systemImage: "list.bullet") { isShowingContents = true }
                    .labelStyle(.iconOnly)
                    .accessibilityHint("Shows the chapter list")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Appearance", systemImage: "textformat.size") { isShowingSettings = true }
                    .labelStyle(.iconOnly)
                    .accessibilityHint("Font, margins and page settings")
            }
        }
    }

    /// Typeface, size, spacing, margins, alignment and page tint.
    struct SettingsSheet: View {
        @Environment(ReaderSettings.self)
        private var settings

        @Environment(\.dismiss)
        private var dismiss

        var body: some View {
            @Bindable var settings = settings

            NavigationStack {
                Form {
                    Section {
                        Picker("Typeface", selection: $settings.face) {
                            ForEach(ReaderSettings.Face.allCases) { face in
                                Text(face.title)
                                    .font(Font(face.font(size: 17)))
                                    .tag(face)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("reader.face")
                        .accessibilityLabel("Typeface")
                    }

                    Section("Size") {
                        Slider(
                            value: $settings.fontSize,
                            in: ReaderSettings.fontSizeRange,
                            step: 1,
                            label: { Text("Font size") },
                            minimumValueLabel: { Text("A").font(.caption) },
                            maximumValueLabel: { Text("A").font(.title3) }
                        )
                        .accessibilityIdentifier("reader.fontSize")
                        .accessibilityLabel("Font size")
                        .accessibilityValue("\(Int(settings.fontSize)) points")
                    }

                    Section("Line spacing") {
                        Slider(value: $settings.lineSpacing, in: 0 ... 16, step: 1)
                            .accessibilityIdentifier("reader.lineSpacing")
                            .accessibilityLabel("Line spacing")
                            .accessibilityValue("\(Int(settings.lineSpacing))")
                    }

                    Section {
                        Slider(value: $settings.margins, in: ReaderSettings.marginRange, step: 1)
                            .accessibilityIdentifier("reader.margins")
                            .accessibilityLabel("Page margins")
                            .accessibilityValue("\(Int(settings.margins)) points")
                    } header: {
                        Text("Margins")
                    } footer: {
                        Text("\(Int(settings.margins)) pt")
                    }

                    Section("Alignment") {
                        Picker("Text alignment", selection: $settings.alignment) {
                            ForEach(ReaderSettings.Alignment.allCases) { alignment in
                                Label(alignment.title, systemImage: alignment.systemImage)
                                    .tag(alignment)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("reader.alignment")
                        .accessibilityLabel("Text alignment")
                    }

                    Section("Page") {
                        ForEach(ReaderSettings.Theme.allCases) { theme in
                            themeRow(theme, isSelected: settings.theme == theme)
                        }
                    }
                }
                .navigationTitle("Appearance")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            // Half height on purpose: the page stays visible above, so every change can be seen
            // landing on the real text rather than on a sample.
            .presentationDetents([ .medium ])
            .presentationBackgroundInteraction(.disabled)
        }

        /// A tappable row per page tint. Explicit rows rather than a `Picker` so each option carries its
        /// own label, swatch and selected state.
        private func themeRow(_ theme: ReaderSettings.Theme, isSelected: Bool) -> some View {
            Button(
                action: { settings.theme = theme },
                label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(theme.background)
                            .frame(width: 26, height: 26)
                            .overlay {
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                            }

                        Text(theme.title)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(.rect)
                }
            )
            .buttonStyle(.plain)
            .accessibilityIdentifier("reader.theme.\(theme.rawValue)")
            .accessibilityLabel(theme.title)
            .accessibilityAddTraits(isSelected ? [ .isButton, .isSelected ] : .isButton)
            .accessibilityHint("Sets the page background")
        }
    }

    /// The chapter list, with the current one marked.
    struct ContentsSheet: View {
        let model: Model

        @Binding
        var isPresented: Bool

        var body: some View {
            NavigationStack {
                List(model.readableChapters) { chapter in
                    Button(
                        action: {
                            isPresented = false
                            Task { await model.open(chapterId: chapter.id) }
                        },
                        label: {
                            HStack {
                                Text(chapter.displayTitle)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if chapter.id == model.currentChapterId {
                                    Image(systemName: "book.fill")
                                        .foregroundStyle(.tint)
                                        .accessibilityHidden(true)
                                }
                            }
                            .contentShape(.rect)
                        }
                    )
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        chapter.id == model.currentChapterId
                            ? "\(chapter.displayTitle), currently reading"
                            : chapter.displayTitle
                    )
                    .accessibilityHint("Opens the chapter")
                }
                .navigationTitle("Contents")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Close") { isPresented = false }
                    }
                }
            }
        }
    }
}
