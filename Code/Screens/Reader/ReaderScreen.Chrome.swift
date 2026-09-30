//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookRenderer
import DesignSystem
import SwiftUI
import Translation

extension ReaderScreen {
    /// Everything of the reader's own that stands over the page: the controls, the way back, the bar
    /// for finding a passage, and the asides a note or picked words call up.
    ///
    /// Laid over the whole window and built the first time any of it is wanted, so opening a book sets
    /// out the page alone. Everything is placed from the same window the page is set against.
    struct Chrome: View {
        let model: Model

        @Bindable
        var stage: Stage

        let close: () -> Void

        @Environment(ReaderSettings.self)
        private var settings

        @FocusState
        private var searchFocused: Bool

        /// How far up the screen the keyboard reaches, which is what the bar stands clear of.
        @State
        private var keyboardCover: CGFloat = 0

        var body: some View {
            Color.clear
                .ignoresSafeArea()
                .overlay(alignment: stage.band.alignment) { controls }
                .overlay(alignment: .bottomLeading) { wayBack }
                .overlay { searching }
                .callout(
                    over: stage.note?.rect ?? .zero,
                    item: $stage.note,
                    ground: calloutGround,
                    coversSafeArea: true
                ) { noteCard($0.note) }
                .callout(
                    over: pickedBox(stage.picked) ?? .zero,
                    item: pickedBinding,
                    ground: calloutGround,
                    coversSafeArea: true,
                    content: { chosen in pickedMenu(chosen) }
                )
                .sensoryFeedback(trigger: stage.picked != nil) { _, shown in shown ? .impact(flexibility: .soft) : nil }
                .sensoryFeedback(trigger: stage.note?.id) { _, shown in
                    shown != nil ? .impact(flexibility: .soft) : nil
                }
                .sheet(item: $stage.lookedUp) { DictionaryView(term: $0.term) }
                .translationPresentation(isPresented: $stage.isTranslating, text: stage.translating)
                #if DEBUG
                    .sheet(item: $stage.report) { ShareSheet(url: $0.url) }
                #endif
                .onChange(of: stage.isSearching, initial: true) { _, searching in
                    if searching { query = model.findQuery }

                    searchFocused = searching
                }
        }

        private var calloutGround: Color {
            Callout<EmptyView>.surface(over: settings.theme.background, with: settings.theme.foreground)
        }

        private var query: String {
            get { stage.query }
            nonmutating set { stage.query = newValue }
        }

        // MARK: - The controls

        /// The controls, built only while they are up.
        ///
        /// Faded out is not gone: a row under glass goes on being read out and found by name however
        /// little of it is drawn.
        @ViewBuilder
        private var controls: some View {
            if !stage.isChromeHidden { chrome.transition(.opacity) }
        }

        @ViewBuilder
        private var chrome: some View {
            if stage.band.isDownASide { downTheSide } else { acrossTheTop }
        }

        private var acrossTheTop: some View {
            HStack(alignment: .top, spacing: Design.Space.large) {
                GlassRow { wayOut }
                    .touchArea("close", on: stage)

                Spacer(minLength: 0)

                GlassRow { marking }
                    .touchArea("marking", on: stage)

                GlassRow { more }
                    .touchArea("more", on: stage)
            }
            // Clear of whatever the device keeps down either side.
            .padding(.leading, stage.safeArea.leading + Design.Space.extraLarge)
            .padding(.trailing, stage.safeArea.trailing + Design.Space.extraLarge)
            .padding(
                .top,
                Self.controlsTop(
                    under: stage.spread.pageSafeArea.top,
                    headSize: stage.runningHeadSize,
                    band: stage.layoutContext.runningHeadBand
                )
            )
            .ignoresSafeArea()
        }

        /// Down the column a folding screen keeps its vertical bar in, where the system stands its own
        /// buttons.
        private var downTheSide: some View {
            VStack(spacing: Design.Space.large) {
                GlassRow(.down) { wayOut }
                    .touchArea("close", on: stage)

                Spacer(minLength: 0)

                GlassRow(.down) { marking }
                    .touchArea("marking", on: stage)

                GlassRow(.down) { more }
                    .touchArea("more", on: stage)
            }
            .padding(.top, Self.statusColumnDepth)
            .padding([ .bottom, stage.band == .leading ? .leading : .trailing ], Design.Space.huge)
            .frame(maxWidth: .infinity, alignment: stage.band.alignment)
            .ignoresSafeArea()
        }

        /// How far down its column the system's status items reach, which no inset reports.
        private static let statusColumnDepth: CGFloat = 120

        /// The way out, since a presented screen has no back button of its own. The glyph is the
        /// gesture: a drag down the page does the same thing.
        private var wayOut: some View {
            Button("Close", systemImage: "chevron.down", action: close)
                .accessibilityIdentifier("reader.close")
                .accessibilityHint("Closes the book")
        }

        /// Whether the book is marked here, and whether it is being read off the device.
        @ViewBuilder
        private var marking: some View {
            if model.isOffline {
                Image(systemName: "wifi.slash")
                    .font(.system(size: Design.Size.glyph(in: Design.Size.touch)))
                    .foregroundStyle(.secondary)
                    .frame(width: Design.Size.touch, height: Design.Size.touch)
                    .accessibilityLabel("Reading from this device")
            }

            let standing = model.bookmarksOnPage

            // One mark is taken off where it stands; several are listed, since which of them to take
            // off is the reader's to say.
            Button(
                standing.count > 1 ? "Bookmarks" : (standing.isEmpty ? "Add bookmark" : "Remove bookmark"),
                systemImage: standing.isEmpty ? "bookmark" : "bookmark.fill"
            ) {
                guard standing.count > 1 else { return model.toggleBookmark() }

                stage.isShowingBookmarks = true
            }
            .accessibilityHint(
                standing.count > 1
                    ? "Lists the marks on the page"
                    : "Marks the page, or clears the mark on it"
            )
            .disabled(!model.canBookmarkPage)
            .popover(isPresented: $stage.isShowingBookmarks) {
                BookmarksSheet(model: model, isPresented: $stage.isShowingBookmarks)
            }
        }

        /// Everything that opens something of its own, under one glyph.
        ///
        /// The forms hang here rather than on the rows in the menu: a menu is gone by the moment its row
        /// acts, and a popover hung on something gone has nothing left to point at.
        private var more: some View {
            Menu {
                Button("Contents", systemImage: "list.bullet") { stage.isShowingContents = true }

                Button("Find", systemImage: "magnifyingglass") { startSearching() }

                Button("Appearance", systemImage: "textformat.size") { stage.isShowingSettings = true }

                #if DEBUG
                    Button("Debug info", systemImage: "ladybug") { collectReport() }
                #endif
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: Design.Size.glyph(in: Design.Size.touch)))
                    .frame(width: Design.Size.touch, height: Design.Size.touch)
                    .contentShape(.rect)
            }
            .accessibilityLabel("More")
            .accessibilityHint("The chapter list, and how the page is set")
            .popover(isPresented: $stage.isShowingContents) {
                ContentsSheet(model: model, isPresented: $stage.isShowingContents)
            }
            .popover(isPresented: $stage.isShowingSettings) { SettingsSheet() }
        }

        // MARK: - The way back

        @ViewBuilder
        private var wayBack: some View {
            if model.wayBack != nil, !stage.isSearching {
                GlassRow {
                    Button("Back to where you were", systemImage: "arrow.uturn.backward") { model.goBack() }
                        .accessibilityIdentifier("reader.wayBack")
                        .accessibilityHint("Returns to the page the link was followed from")
                }
                .touchArea("wayBack", on: stage)
                .padding(.leading, stage.safeArea.leading + Design.Space.extraLarge)
                .padding(
                    .bottom,
                    Self.controlsBottom(
                        over: stage.spread.pageSafeArea.bottom,
                        headSize: stage.runningHeadSize,
                        band: stage.layoutContext.runningHeadBand
                    )
                )
                .ignoresSafeArea()
                .opacity(stage.fading ? 0 : 1)
                .transition(.opacity)
            }
        }

        // MARK: - Finding

        /// The bar for finding a passage, standing on the line the page number is set on.
        @ViewBuilder
        private var searching: some View {
            if stage.isSearching {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    SearchBar(model: model, query: $stage.query, focused: $searchFocused, onClose: stopSearching)
                        .touchArea("search", on: stage)
                        .padding(.horizontal, stage.safeArea.leading + Design.Space.extraLarge)
                        // Whichever stands deeper, the device's own band or the keyboard: the keyboard is
                        // measured from the foot of the window and covers the band already.
                        .padding(
                            .bottom,
                            max(stage.spread.pageSafeArea.bottom + Self.headInset, keyboardCover + Design.Space.medium)
                        )
                }
                .ignoresSafeArea()
                .keyboardCover($keyboardCover)
                .transition(.opacity)
            }
        }

        private func startSearching() {
            withAnimation(.easeInOut(duration: Stage.chromeFade)) { stage.isSearching = true }
        }

        private func stopSearching() {
            searchFocused = false
            withAnimation(.easeInOut(duration: Stage.chromeFade)) { stage.isSearching = false }
            model.stopFinding()
        }

        // MARK: - Asides

        /// Everything the reader picked out, as one box for an aside to stand clear of, in the sheet's
        /// coordinates rather than in those of the page the words came off.
        private func pickedBox(_ chosen: Model.PickedText?) -> CGRect? {
            guard let chosen, let bounds = CalloutPlacement.bounds(around: chosen.rects) else { return nil }

            let column = model.pagesOnScreen.firstIndex { $0.id == chosen.pageId } ?? 0

            return stage.spread.onSheet(bounds, column: column)
        }

        /// Putting the menu away takes the paint under the words with it.
        private var pickedBinding: Binding<Model.PickedText?> {
            Binding(
                get: { stage.picked },
                set: { chosen in
                    withAnimation(chosen == nil ? CalloutMotion.hiding : CalloutMotion.showing) {
                        stage.picked = chosen
                    }

                    if chosen == nil { model.clearPicked() }
                }
            )
        }

        private func clearPicked() {
            withAnimation(CalloutMotion.hiding) { stage.picked = nil }
            model.clearPicked()
        }

        /// What can be done with the words the reader drew a finger across.
        private func pickedMenu(_ chosen: Model.PickedText) -> some View {
            Callout(
                foreground: settings.theme.foreground,
                background: settings.theme.background,
                content: {
                    VStack(alignment: .leading, spacing: Design.Space.small) {
                        action("Look up", systemImage: "character.book.closed") {
                            stage.lookedUp = LookedUpTerm(term: chosen.selection.text)
                        }

                        action("Translate", systemImage: "translate") {
                            stage.translating = chosen.selection.text
                            stage.isTranslating = true
                        }

                        action("Copy", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = chosen.selection.text
                        }

                        action("Add bookmark", systemImage: "bookmark") { model.bookmarkPicked() }
                    }
                }
            )
            .accessibilityIdentifier("reader.picked")
        }

        private func action(
            _ title: LocalizedStringKey,
            systemImage: String,
            perform: @escaping () -> Void
        ) -> some View {
            Button {
                perform()
                clearPicked()
            } label: {
                Label(title, systemImage: systemImage)
                    .font(Design.Style.item)
                    .foregroundStyle(settings.theme.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Design.Size.control)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }

        /// A note, in the page's own colours and face: these are the book's words, not the app's chrome.
        private func noteCard(_ note: BookNote) -> some View {
            Callout(
                foreground: settings.theme.foreground,
                background: settings.theme.background,
                content: { BookTextView(text: note.text, style: noteStyle, width: Design.Size.calloutText) }
            )
            .accessibilityIdentifier("reader.note")
            .accessibilityLabel("Note \(note.marker)")
        }

        /// A note is set the way the page is and only a shade smaller, being an aside.
        private var noteStyle: ChapterTextStyle {
            var style = settings.textStyle

            style.fontSize *= Self.noteScale
            style.lineSpacing *= Self.noteScale
            // A note is one aside standing on its own, with nothing above it to be told apart from.
            style.indentsParagraphs = false
            return style
        }

        private static let noteScale = 0.88

        // MARK: - Where the controls stand

        /// Where the controls start, so that the middle of them lands on the middle of the line the
        /// running head is set on. The head sits its own inset below the safe area.
        static func controlsTop(under safeAreaTop: CGFloat, headSize: CGFloat, band: CGFloat) -> CGFloat {
            safeAreaTop + RunningHead.air(band, headSize) + (headLine(headSize) - Design.Size.touch) / 2
        }

        /// Where the way back stands, so its middle lands on the middle of the line the page number is
        /// set on.
        static func controlsBottom(over safeAreaBottom: CGFloat, headSize: CGFloat, band: CGFloat) -> CGFloat {
            safeAreaBottom + RunningHead.air(band, headSize * Stage.captionScale)
                + (headLine(headSize * Stage.captionScale) - Design.Size.touch) / 2
        }

        /// The line a running head of this size is set on, which is taller than the type itself.
        static func headLine(_ headSize: CGFloat) -> CGFloat { RunningHead.line(headSize) }

        /// What the running head keeps between itself and the safe area.
        static let headInset: CGFloat = RunningHead.inset

        // MARK: - Debug

        #if DEBUG
            /// The page, what it was set with and a picture of it, zipped and offered to share.
            private func collectReport() {
                // The bar would otherwise stand in the picture, and the page is what is being asked about.
                stage.isChromeHidden = true

                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))

                    let markup = await model.chapterMarkup()

                    guard
                        let url = try? DebugReport.make(
                            pageText: model.pageText,
                            settings: settingsReport,
                            lines: linesReport,
                            layout: layoutReport,
                            markup: markup
                        )
                    else {
                        return
                    }

                    stage.report = SharedFile(url: url)
                }
            }

            /// Where the page's size came from and what each page on screen was cut against.
            private var layoutReport: String {
                let scene = UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene
                let window = scene?.keyWindow
                let bounds = window?.bounds.size ?? .zero
                let insets = window?.safeAreaInsets ?? .zero
                let asked = stage.layoutContext.textSize

                return """
                    window: \(bounds.width) x \(bounds.height), insets \(insets.top), \(insets.left), \
                    \(insets.bottom), \(insets.right)
                    sheet: \(stage.sheetSize.width) x \(stage.sheetSize.height), page insets \(stage.safeArea.top), \
                    \(stage.safeArea.bottom)
                    band: \(String(describing: stage.band))
                    chrome hidden: \(stage.isChromeHidden), status bar hidden: \(stage.hidesStatusBar)
                    view asks for text: \(asked.width) x \(asked.height)
                    \(model.layoutReport)
                    """
            }

            /// Each line as it was set, against the measure it was set to.
            private var linesReport: String {
                let measure = stage.layoutContext.textSize.width

                return model.pageLines.enumerated()
                    .map { index, line in
                        let gap = measure - line.width
                        let gaps = String(format: "gaps=%d×%.2f", line.gaps, line.gapMultiple)
                        let flags =
                            "starts=\(line.startsParagraph) ends=\(line.endsParagraph) "
                            + "just=\(line.isJustified) head=\(line.isHeading)"
                        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let why = line.shortReason.map { "\t[\($0)]" } ?? ""

                        return "\(index)\tw=\(Int(line.width))\tgap=\(Int(gap))\t\(gaps)\t\(flags)\(why)\t\(text)"
                    }
                    .joined(separator: "\n")
            }

            private var settingsReport: String {
                let style = settings.textStyle
                let context = stage.layoutContext
                let language = model.chapterLanguage

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
                    runningHeadBand: \(context.runningHeadBand)
                    typographyVersion: \(Typography.version)
                    chapter: \(model.currentChapterId.map(String.init) ?? "nil")
                    offset: \(model.currentSheet?.start.offset.description ?? "nil")
                    """
            }
        #endif
    }
}

private extension View {
    /// Tells the stage where this takes touches, so the layer it stands in passes every other touch on
    /// to the page underneath.
    func touchArea(_ name: String, on stage: ReaderScreen.Stage) -> some View {
        onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { stage.touchAreas[name] = $0 })
            .onDisappear { stage.touchAreas[name] = nil }
    }
}
