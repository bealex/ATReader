//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import BookKit
import BookRenderer
import DesignSystem
import SwiftUI
import Translation
import UIKit

enum ReaderScreen {
    /// The reader for a screen SwiftUI builds, such as one pushed onto a stack.
    struct Component: UIViewControllerRepresentable {
        let workId: Int
        let title: String
        let initialChapterId: Int?

        @Environment(SessionStore.self)
        private var session

        @Environment(ReaderSettings.self)
        private var settings

        @Environment(Navigator.self)
        private var navigator

        @Environment(\.pagePictures)
        private var pictures

        func makeUIViewController(context: Context) -> Controller {
            Controller(
                workId: workId,
                title: title,
                initialChapterId: initialChapterId,
                session: session,
                settings: settings,
                navigator: navigator,
                pictures: pictures
            )
        }

        func updateUIViewController(_ controller: Controller, context: Context) {}
    }

    /// The appearance form over the page, with a way to put it away.
    struct SettingsSheet: View {
        @Environment(\.dismiss)
        private var dismiss

        var body: some View {
            NavigationStack {
                Appearance()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
            }
            // Read only where this stands beside the button rather than over the book: a popover is
            // asked how big it wants to be, and a sheet is told.
            .frame(idealWidth: Self.wide, idealHeight: Self.deep)
            // Half height on purpose where it does cover the book: the page stays visible above, so
            // every change can be seen landing on the real text rather than on a sample.
            .presentationDetents([ .medium ])
            .presentationCompactAdaptation(.sheet)
            .presentationBackgroundInteraction(.disabled)
        }

        static let wide: CGFloat = 380
        static let deep: CGFloat = 520
    }

    /// How the text is set, what colours it is set in, and what the screen does with it.
    struct Appearance: View {
        /// Which of the three the sheet is showing.
        ///
        /// Three panels rather than one long form: the sheet is half the screen on purpose, so the page
        /// behind it can be watched, and everything below the first scroll of a form is out of sight.
        private enum Panel: String, CaseIterable, Identifiable {
            case type
            case colour
            case interactions
            case options

            var id: String { rawValue }

            var title: String {
                switch self {
                    case .type: String(localized: "Type")
                    case .colour: String(localized: "Colour")
                    case .interactions: String(localized: "Interactions")
                    case .options: String(localized: "Options")
                }
            }
        }

        @Environment(ReaderSettings.self)
        private var settings

        @State
        private var panel: Panel = .type

        var body: some View {
            Form {
                switch panel {
                    case .type: typePanel
                    case .colour: colourPanel
                    case .interactions: interactionsPanel
                    case .options: optionsPanel
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { panels }
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
        }

        /// Always on screen, since it says where the rest of the sheet is.
        private var panels: some View {
            Picker("Settings", selection: $panel) {
                ForEach(Panel.allCases) { panel in
                    Text(panel.title).tag(panel)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(.bar)
            .accessibilityIdentifier("reader.panel")
        }

        // MARK: - Type

        @ViewBuilder
        private var typePanel: some View {
            @Bindable var settings = settings

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

            Section {
                SteppedSlider(
                    value: $settings.fontSize,
                    in: ReaderSettings.fontSizeRange,
                    step: 1,
                    nudge: 1,
                    identifier: "reader.fontSize",
                    label: "Text size",
                    spoken: "\(Int(settings.fontSize)) points"
                )
            } header: {
                setting("Text size", at: settings.fontSize)
            }

            Section {
                SteppedSlider(
                    value: $settings.lineSpacing,
                    in: ReaderSettings.lineSpacingRange,
                    step: 1,
                    nudge: 1,
                    identifier: "reader.lineSpacing",
                    label: "Line spacing",
                    spoken: "\(Int(settings.lineSpacing))"
                )
            } header: {
                setting("Line spacing", at: settings.lineSpacing)
            }

            Section {
                SteppedSlider(
                    value: $settings.letterSpacing,
                    in: ReaderSettings.letterSpacingRange,
                    step: 0.1,
                    nudge: 0.1,
                    identifier: "reader.letterSpacing",
                    label: "Letter spacing",
                    spoken: "\(settings.letterSpacing.formatted(.number.precision(.fractionLength(1)))) points"
                )
            } header: {
                setting("Letter spacing", at: settings.letterSpacing, fraction: 1)
            }

            Section {
                SteppedSlider(
                    value: $settings.margins,
                    in: ReaderSettings.marginRange,
                    step: 1,
                    nudge: 4,
                    identifier: "reader.margins",
                    label: "Page margins",
                    spoken: "\(Int(settings.margins)) points"
                )
            } header: {
                setting("Page margins", at: settings.margins)
            }

            Section("Alignment") {
                alignmentPicker("Russian", selection: $settings.russianAlignment, key: "ru")
                alignmentPicker("English", selection: $settings.englishAlignment, key: "en")

                Toggle("Hyphenation", isOn: $settings.hyphenates)
                    .accessibilityIdentifier("reader.hyphenates")
                    .accessibilityHint("Lets a word break at the end of a line")
            }
        }

        // MARK: - Colour

        @ViewBuilder
        private var colourPanel: some View {
            @Bindable var settings = settings

            Section {
                Toggle("Follow the system", isOn: $settings.followsSystem)
                    .accessibilityIdentifier("reader.followsSystem")
                    .accessibilityHint("Reads one theme by day and another by night, as the system does")
            }

            // Two themes where the page follows the system, since that is the whole of what following
            // it means: which one to turn to when it turns.
            if settings.followsSystem {
                Section("While the system is light") {
                    themes(picked: settings.lightTheme, named: "light") { settings.lightTheme = $0 }
                }

                Section("While the system is dark") {
                    themes(picked: settings.darkTheme, named: "dark") { settings.darkTheme = $0 }
                }
            } else {
                Section("Theme") {
                    themes(picked: settings.fixedTheme, named: "fixed") { settings.fixedTheme = $0 }
                }
            }
        }

        // MARK: - Options

        @ViewBuilder
        private var optionsPanel: some View {
            @Bindable var settings = settings

            Section("Screen") {
                Toggle("Keep the page upright", isOn: $settings.isPortraitOnly)
                    .accessibilityIdentifier("reader.portraitOnly")
                    .accessibilityHint("Holds the page still when the device is turned")
            }

            Section("Pictures") {
                Toggle("In the page’s colours", isOn: $settings.monochromeImages)
                    .accessibilityIdentifier("reader.monochromeImages")
                    .accessibilityHint("Draws every picture in the two colours the page is set in")
            }
        }

        // MARK: - Interactions

        @ViewBuilder
        private var interactionsPanel: some View {
            @Bindable var settings = settings

            Section("Tapping") {
                Toggle("Left tap advances", isOn: $settings.advancesOnLeftTap)
                    .accessibilityIdentifier("reader.advancesOnLeftTap")
                    .accessibilityHint("Turns forward on either side of the page, or back on the left")
            }
        }

        // MARK: - The pieces

        /// A section's own name with the value its slider stands at, so a setting can be read as well
        /// as felt for.
        private func setting(_ title: LocalizedStringResource, at value: Double, fraction: Int = 0) -> Text {
            let points = value.formatted(.number.precision(.fractionLength(fraction)))

            return Text(verbatim: "\(String(localized: title)) (\(String(localized: "\(points) pt")))")
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

        @ViewBuilder
        private func themes(
            picked: ReaderSettings.Theme,
            named: String,
            choose: @escaping (ReaderSettings.Theme) -> Void
        ) -> some View {
            ForEach(ReaderSettings.Theme.allCases) { theme in
                themeRow(theme, isSelected: theme == picked, named: named, choose: choose)
            }
        }

        /// A tappable row per page tint. Explicit rows rather than a `Picker` so each option carries its
        /// own label, swatch and selected state.
        private func themeRow(
            _ theme: ReaderSettings.Theme,
            isSelected: Bool,
            named: String,
            choose: @escaping (ReaderSettings.Theme) -> Void
        ) -> some View {
            Button(
                action: { choose(theme) },
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
            .accessibilityIdentifier("reader.theme.\(named).\(theme.rawValue)")
            .accessibilityLabel(theme.title)
            .accessibilityAddTraits(isSelected ? [ .isButton, .isSelected ] : .isButton)
            .accessibilityHint("Sets the colours the page is drawn in")
        }
    }

    /// The marks standing on the page, and a way to take any of them off.
    ///
    /// Only ever shown for several of them: one mark is taken off by the button that shows it.
    struct BookmarksSheet: View {
        let model: Model

        @Binding
        var isPresented: Bool

        var body: some View {
            NavigationStack {
                List {
                    ForEach(model.bookmarksOnPage) { mark in
                        HStack(spacing: Design.Space.medium) {
                            BookmarkLabel(
                                share: mark.share(ofChapterLength: model.length(ofChapter: mark.chapterId)),
                                text: mark.text
                            )

                            Button("Remove bookmark", systemImage: "trash") { remove(mark) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.plain)
                                .foregroundStyle(.red)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Remove", systemImage: "bookmark.slash", role: .destructive) { remove(mark) }
                        }
                    }
                }
                .navigationTitle("Bookmarks")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Close") { isPresented = false }
                    }
                }
            }
            .frame(idealWidth: SettingsSheet.wide, idealHeight: SettingsSheet.deep)
            .presentationCompactAdaptation(.sheet)
            .accessibilityIdentifier("reader.bookmarks")
        }

        private func remove(_ mark: Bookmark) {
            model.remove([ mark ])

            // Nothing left to choose between: the list puts itself away.
            if model.bookmarksOnPage.count < 2 { isPresented = false }
        }
    }

    /// The chapter list, with the current one marked.
    struct ContentsSheet: View {
        let model: Model

        @Binding
        var isPresented: Bool

        var body: some View {
            NavigationStack {
                List {
                    let chapters = model.readableChapters
                    let names = chapters.contentsNames()

                    ForEach(Array(chapters.enumerated()), id: \.element.id) { place, chapter in
                        chapterRow(chapter, named: names[place])

                        ForEach(model.bookmarks(inChapter: chapter.id)) { mark in
                            bookmarkRow(mark)
                        }
                    }
                }
                .navigationTitle("Contents")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Close") { isPresented = false }
                    }
                }
            }
            .frame(idealWidth: SettingsSheet.wide, idealHeight: SettingsSheet.deep)
            .presentationCompactAdaptation(.sheet)
        }

        private func chapterRow(_ chapter: BookChapter, named name: String) -> some View {
            Button(
                action: {
                    isPresented = false
                    model.open(chapterId: chapter.id)
                },
                label: {
                    HStack {
                        Text(name)
                            // What a book marked inside a chapter stands under it, so the shape of the
                            // book is in the list rather than only its pieces.
                            .padding(.leading, Design.Space.large * CGFloat(chapter.contentsLevel - 1))
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
                    ? "\(name), currently reading"
                    : name
            )
            .accessibilityHint("Opens the chapter")
        }

        /// A mark under the chapter it stands in, and how far into that chapter it is.
        private func bookmarkRow(_ mark: Bookmark) -> some View {
            Button(
                action: {
                    isPresented = false
                    model.open(chapterId: mark.chapterId, anchor: .offset(model.opening(of: mark)))
                },
                label: {
                    BookmarkLabel(
                        share: mark.share(ofChapterLength: model.length(ofChapter: mark.chapterId)),
                        text: mark.text
                    )
                }
            )
            .buttonStyle(.plain)
            .accessibilityHint("Opens the book here")
            .swipeActions(edge: .trailing) {
                Button("Remove", systemImage: "bookmark.slash", role: .destructive) { model.remove([ mark ]) }
            }
            .contextMenu {
                Button("Remove bookmark", systemImage: "bookmark.slash", role: .destructive) {
                    model.remove([ mark ])
                }
            }
        }
    }
}
