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

        /// The notch and home-indicator bands, taken from the window rather than the layout: a toolbar
        /// coming and going would otherwise re-paginate the chapter.
        @State
        private var safeArea = EdgeInsets()

        /// A page fills the screen, and the controls are a tap in the middle away.
        @State
        private var isChromeHidden = true

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
            .toolbar(isChromeHidden ? .hidden : .visible, for: .navigationBar)
            .backSwipeDisabled()
            .statusBarHidden(isChromeHidden)
            .toolbar { toolbar }
            .toolbarBackground(settings.theme.background, for: .navigationBar)
            // The page runs under the bar, so the bar needs a background of its own or the book's
            // title shows through the chapter's.
            .toolbarBackground(.visible, for: .navigationBar)
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

            pageArea($model)
                .overlay {
                    if model.isLoading && model.layout == nil {
                        ProgressView("Loading chapter…")
                            .accessibilityLabel("Loading chapter")
                    } else if let message = model.errorMessage, model.layout == nil {
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
                hasPageBefore: value.hasPageBefore,
                hasPageAfter: value.hasPageAfter,
                onPastEnd: value.goToNextChapter,
                onPastStart: value.goToPreviousChapter,
                onMiddleTap: toggleChrome,
                page: { index in pageContent(value, at: index) }
            )
            .accessibilityIdentifier("reader.page")
            .ignoresSafeArea()
            // The window, not the layout: a page ignores the safe area, so the size its parent hands
            // it is not the size it draws at, and a toolbar coming and going would move it besides.
            .onGeometryChange(for: CGSize.self, of: { $0.size }, action: { _ in applyWindowMetrics() })
            .onChange(of: layoutContext, initial: true) { value.apply(context: layoutContext) }
        }

        /// One page, drawn edge to edge: the text, the book's title above it and the page number below.
        /// Both run with the page rather than sitting in chrome around it, so a turn moves everything.
        @ViewBuilder
        private func pageContent(_ model: Model, at index: Int) -> some View {
            let footer = model.caption(at: index)
            let isCurrent = index == model.currentPage

            switch model.page(at: index) {
                case .title:
                    BookTitlePageView(
                        title: model.book?.title ?? title,
                        author: model.book?.authorLine ?? "",
                        seriesTitle: model.book?.seriesTitle,
                        coverURL: model.book?.coverURL,
                        style: settings.textStyle,
                        margins: settings.margins,
                        safeArea: safeArea
                    )
                    .background(settings.theme.background)
                    .overlay(alignment: .bottom) { runningHead(footer, edge: .bottom, isCaption: isCurrent) }
                case let .text(layout, page):
                    ChapterPageView(layout: layout, pageIndex: page)
                        .background(settings.theme.background)
                        .overlay(alignment: .top) { runningHead(model.book?.title ?? title, edge: .top) }
                        .overlay(alignment: .bottom) { runningHead(footer, edge: .bottom, isCaption: isCurrent) }
                case .blank:
                    settings.theme.background
            }
        }

        /// The book title above the text, or the page number below it.
        @ViewBuilder
        private func runningHead(_ text: String?, edge: VerticalEdge, isCaption: Bool = false) -> some View {
            if let text, !text.isEmpty {
                Text(text)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(settings.theme.foreground.opacity(0.4))
                    .padding(.horizontal, settings.margins)
                    .padding(.top, edge == .top ? safeArea.top + 4 : 0)
                    .padding(.bottom, edge == .bottom ? safeArea.bottom + 4 : 0)
                    .frame(maxWidth: .infinity)
                    // Only the page the reader is on names itself, so a turn never puts two of these
                    // on screen under the same identifier.
                    .accessibilityIdentifier(isCaption ? "reader.caption" : "")
                    .accessibilityHidden(!isCaption)
            }
        }

        private func toggleChrome() {
            withAnimation(.easeInOut(duration: 0.2)) { isChromeHidden.toggle() }
        }

        /// Everything pagination depends on. A change to any of it re-lays the chapter.
        private var layoutContext: ChapterLayout.Context {
            ChapterLayout.Context(
                style: settings.textStyle,
                margins: settings.margins,
                pageSize: pageSize,
                safeArea: safeArea
            )
        }

        /// Takes the page's size and the device's own insets from the window, which keeps both whatever
        /// chrome is on screen.
        private func applyWindowMetrics() {
            let scene = UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene

            guard let window = scene?.keyWindow else { return }

            let insets = window.safeAreaInsets
            safeArea = EdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
            pageSize = window.bounds.size
        }

        @ToolbarContentBuilder
        private var toolbar: some ToolbarContent {
            // The title stays while the controls are away, greyed back so it reads as a marker rather
            // than a heading.
            ToolbarItem(placement: .principal) {
                Text(model?.chapterTitle ?? title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(settings.theme.foreground.opacity(isChromeHidden ? 0.35 : 1))
            }

            if !isChromeHidden {
                if model?.isOffline == true {
                    ToolbarItem(placement: .topBarLeading) {
                        Image(systemName: "wifi.slash")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Reading from this device")
                    }
                }

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
                            model.open(chapterId: chapter.id)
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
