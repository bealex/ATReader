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

        @Environment(\.scenePhase)
        private var scenePhase

        @State
        private var model: Model?

        @State
        private var isShowingSettings = false

        @State
        private var isShowingContents = false

        #if DEBUG
            @State
            private var report: SharedFile?
        #endif

        @State
        private var pageSize: CGSize = .zero

        /// The notch and home-indicator bands, taken from the window rather than the layout: a toolbar
        /// coming and going would otherwise re-paginate the chapter.
        @State
        private var safeArea = EdgeInsets()

        /// A page fills the screen, and the controls are a tap in the middle away.
        @State
        private var isChromeHidden = true

        /// The type size of the running head, which ``ChapterLayout/Context/runningHeadHeight`` keeps
        /// the body text clear of.
        @ScaledMetric(relativeTo: .caption2)
        private var runningHeadSize: CGFloat = 18.7

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
            // The system's own bar, so its buttons sit and size themselves the way they do elsewhere.
            .toolbar(isChromeHidden ? .hidden : .visible, for: .navigationBar)
            // The page's colour behind the bar, with a shadow to part it from the page: the running
            // head passes under it, and glass would show that through.
            .readerBarAppearance(
                background: settings.theme.background,
                colorScheme: settings.theme.colorScheme,
                isVisible: !isChromeHidden
            )
            .toolbar { controls }
            .backSwipeDisabled()
            .statusBarHidden(isChromeHidden)
            .sheet(isPresented: $isShowingSettings) { SettingsSheet() }
            #if DEBUG
                .sheet(item: $report) { ShareSheet(url: $0.url) }
            #endif
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
            // Where the reader stopped is worth writing the moment they stop: an app on its way to
            // the background will not run a task that is still waiting.
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { model?.flushPosition() }
            }
            .onDisappear { model?.flushPosition() }
        }

        @ViewBuilder
        private func page(_ model: Model) -> some View {
            @Bindable var model = model

            pageArea($model)
                .overlay {
                    if let progress = model.paginationProgress {
                        paginationCard(progress)
                    } else if model.isLoading && model.layout == nil {
                        LoadingOverlay(
                            title: "Loading chapter…",
                            label: "Loading chapter",
                            background: settings.theme.background
                        )
                    } else if let message = model.errorMessage, model.layout == nil {
                        ContentUnavailableView("Couldn’t open", systemImage: "book.closed", description: Text(message))
                    }
                }
        }

        /// What the reader sees while the book is being measured.
        ///
        /// On a card, because the first page it covers is the title page and a bar drawn straight onto
        /// the cover is unreadable. The page's own colours rather than a material, which would follow
        /// the system's light or dark instead of the theme the reader chose.
        private func paginationCard(_ progress: Double) -> some View {
            VStack(spacing: 12) {
                Text("Setting the pages…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(settings.theme.foreground)

                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(settings.theme.foreground)

                Text(progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(settings.theme.foreground.opacity(0.55))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: 280)
            .background(settings.theme.background, in: .rect(cornerRadius: 18))
            // A card the same colour as the page needs an edge, the same way the bar above it does.
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(settings.theme.foreground.opacity(0.15), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("reader.pagination")
            .accessibilityLabel("Setting the pages")
            .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
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
                onTurnStarted: {
                    hideChrome()
                    value.noteTurn()
                },
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
                case let .text(pieces):
                    // Two pieces where a chapter starts on the page the one before it ended on. Each
                    // draws only its own lines, in its own place on the page.
                    ZStack {
                        ForEach(pieces) { piece in
                            ChapterPageView(layout: piece.layout, pageIndex: piece.page)
                        }
                    }
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
                    .font(.system(size: runningHeadSize))
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
            withAnimation(.easeInOut(duration: Self.chromeFade)) { isChromeHidden.toggle() }
        }

        /// Turning a page is reading, so the controls get out of the way.
        private func hideChrome() {
            guard !isChromeHidden else { return }

            withAnimation(.easeInOut(duration: Self.chromeFade)) { isChromeHidden = true }
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

        /// How long the controls take to fade in or out.
        private static let chromeFade: Double = 0.25

        /// The bar's own controls. Back and the chapter's name come from the navigation stack.
        @ToolbarContentBuilder
        private var controls: some ToolbarContent {
            if model?.isOffline == true {
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "wifi.slash")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Reading from this device")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Contents", systemImage: "list.bullet") { isShowingContents = true }
                    .accessibilityHint("Shows the chapter list")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Appearance", systemImage: "textformat.size") { isShowingSettings = true }
                    .accessibilityHint("Font, margins and page settings")
            }

            #if DEBUG
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Debug info", systemImage: "ladybug") { collectReport() }
                        .accessibilityHint("Collects the page, its settings and a picture of it")
                }
            #endif
        }

        #if DEBUG
            /// The page, what it was set with and a picture of it, zipped and offered to share.
            private func collectReport() {
                guard let model else { return }

                // The bar would otherwise stand in the picture, and the page is what is being asked about.
                isChromeHidden = true

                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))

                    guard
                        let url = try? DebugReport.make(
                            pageText: model.pageText,
                            settings: settingsReport,
                            lines: linesReport(model)
                        )
                    else {
                        return
                    }

                    report = SharedFile(url: url)
                }
            }

            /// Each line as it was set, against the measure it was set to.
            private func linesReport(_ model: Model) -> String {
                let measure = layoutContext.textSize.width

                return model.pageLines.enumerated()
                    .map { index, line in
                        let gap = measure - line.width
                        let flags =
                            "starts=\(line.startsParagraph) ends=\(line.endsParagraph) "
                            + "just=\(line.isJustified) head=\(line.isHeading)"
                        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)

                        let why = line.shortReason.map { "\t[\($0)]" } ?? ""

                        return "\(index)\tw=\(Int(line.width))\tgap=\(Int(gap))\t\(flags)\(why)\t\(text)"
                    }
                    .joined(separator: "\n")
            }

            private var settingsReport: String {
                let style = settings.textStyle
                let context = layoutContext
                let language = model?.chapterLanguage

                return """
                    face: \(style.face.rawValue) \(style.weight.rawValue)
                    fontSize: \(style.fontSize)
                    lineSpacing: \(style.lineSpacing)
                    letterSpacing: \(style.letterSpacing)
                    margins: \(settings.margins)
                    alignment.ru: \(settings.russianAlignment.rawValue)
                    alignment.en: \(settings.englishAlignment.rawValue)
                    theme: \(settings.theme.rawValue)
                    language: \(language ?? "nil")
                    justifies: \(style.justifies(language))
                    pageSize: \(context.pageSize.width) x \(context.pageSize.height)
                    safeArea: \(context.safeArea.top), \(context.safeArea.leading), \
                    \(context.safeArea.bottom), \(context.safeArea.trailing)
                    textSize: \(context.textSize.width) x \(context.textSize.height)
                    runningHeadHeight: \(ChapterLayout.Context.runningHeadHeight)
                    rulesVersion: \(ChapterLayout.rulesVersion)
                    typographyVersion: \(Typography.version)
                    fingerprint: \(context.fingerprint)
                    chapter: \(model?.currentChapterId.map(String.init) ?? "nil")
                    page: \((model?.currentPage ?? 0) + 1) of \(model?.pageCount ?? 0)
                    """
            }
        #endif
    }

    /// Typeface, size, spacing, margins, alignment and page tint.
    struct SettingsSheet: View {
        @Environment(ReaderSettings.self)
        private var settings

        @Environment(\.scenePhase)
        private var scenePhase

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

                        Picker("Weight", selection: $settings.weight) {
                            ForEach(settings.face.weights) { weight in
                                Text(settings.face.title(for: weight))
                                    .font(Font(settings.face.font(size: 17, weight: weight.uiWeight)))
                                    .tag(weight)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("reader.weight")
                        .accessibilityLabel("Font weight")
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

                    Section("Letter spacing") {
                        Slider(value: $settings.letterSpacing, in: ReaderSettings.letterSpacingRange, step: 0.1)
                            .accessibilityIdentifier("reader.letterSpacing")
                            .accessibilityLabel("Letter spacing")
                            .accessibilityValue(
                                "\(settings.letterSpacing.formatted(.number.precision(.fractionLength(1)))) points"
                            )
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
                        alignmentPicker("Russian", selection: $settings.russianAlignment, key: "ru")
                        alignmentPicker("English", selection: $settings.englishAlignment, key: "en")
                    }

                    Section("Screen") {
                        Toggle("Portrait only", isOn: $settings.isPortraitOnly)
                            .accessibilityIdentifier("reader.portraitOnly")
                            .accessibilityHint("Keeps the page upright when the device is turned")
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

        /// Alignment is set per language: a language's own typography decides whether justifying it
        /// reads well, and a reader with books in both wants both answers kept.
        private func alignmentPicker(
            _ title: LocalizedStringKey,
            selection: Binding<ReaderSettings.Alignment>,
            key: String
        ) -> some View {
            LabeledContent(title) {
                // A segmented picker inside a form drops its own label, so the language it belongs to
                // has to be a label of its own.
                Picker(title, selection: selection) {
                    ForEach(ReaderSettings.Alignment.allCases) { alignment in
                        Image(systemName: alignment.systemImage)
                            .accessibilityLabel(alignment.title)
                            .tag(alignment)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 130)
                .accessibilityIdentifier("reader.alignment.\(key)")
            }
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
