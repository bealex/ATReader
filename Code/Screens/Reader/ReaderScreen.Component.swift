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

        @Environment(Navigator.self)
        private var navigator

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
        private var sheetSize: CGSize = .zero

        /// The notch and home-indicator bands, taken from the window rather than the layout: a toolbar
        /// coming and going would otherwise re-paginate the chapter.
        @State
        private var safeArea = EdgeInsets()

        /// The edge the system keeps its vertical bar on, nil where it keeps none.
        @State
        private var barEdge: HorizontalEdge?

        /// A page fills the screen, and the controls are a tap in the middle away.
        @State
        private var isChromeHidden = true

        /// True while the way back is on its way out.
        @State
        private var fading = false

        @State
        private var wayBackFade: Task<Void, Never>?

        /// The note a marker was tapped for, which carries where that marker stands so the aside can
        /// point at it.
        @State
        private var note: Model.TappedNote?

        /// Text picked off the page, once the finger has come up and there is something to offer.
        @State
        private var picked: Model.PickedText?

        @State
        private var lookedUp: LookedUpTerm?

        /// True while the bar for finding a passage stands at the foot of the page.
        @State
        private var isSearching = false

        @State
        private var keyboardCover: CGFloat = 0

        @State
        private var query = ""

        @FocusState
        private var searchFocused: Bool

        /// How far up the screen the keyboard reaches, which is what the bar stands clear of.
        @State
        private var isTranslating = false

        @State
        private var translating = ""

        /// True while something of the reader's own stands over the page.
        ///
        /// The press that picks text out hangs on the window, so anything shown over the page has to
        /// say so here or a finger held on it goes on choosing words underneath.
        private var isPageCovered: Bool {
            #if DEBUG
                if report != nil { return true }
            #endif

            return isShowingContents || isShowingSettings || lookedUp != nil || isTranslating
        }

        /// The type size of the running head, which ``ChapterLayout/Context/runningHeadBand`` keeps the
        /// body text clear of. Both are read off the book's own text size, so the band is always as
        /// deep as the head standing in it.
        private var runningHeadSize: CGFloat {
            settings.fontSize * ChapterLayout.Context.runningHeadScale
        }

        @Environment(\.dismiss)
        private var dismiss

        var body: some View {
            // A stack of the reader's own. It is presented over the app rather than pushed into it,
            // so there is no other one to draw its bar.
            NavigationStack {
                Group {
                    if let model {
                        page(model)
                    } else {
                        Color.clear
                    }
                }
                .background(settings.theme.background.ignoresSafeArea())
                // Over the stack rather than over the page. Everything the reader draws is laid out
                // against the window, this included, so the bar is stood at the foot of a layer of its
                // own rather than handed to the safe area.
                .overlay { if let model { searching(model) } }
                // The stack is here for the window it gives the page, not for a bar. A bar centres its
                // buttons on its own height and ignores anything asking them to sit elsewhere, so the
                // reader draws its own and stands them on the line the running head is set on.
                .toolbar(.hidden, for: .navigationBar)
                // The page's colour under the corners the stack rounds, and the window held to the
                // page's own light or dark.
                .readerBarAppearance(
                    background: settings.theme.background,
                    colorScheme: settings.theme.colorScheme,
                    isVisible: false
                )
                .statusBarHidden(hidesStatusBar)
                #if DEBUG
                    .sheet(item: $report) { ShareSheet(url: $0.url) }
                #endif
                // Written as the book starts closing rather than once it has closed: the shelf draws
                // the mark on a cover from the store and the zoom photographs that cover on its way in.
                .onAppear {
                    if model == nil {
                        model = Model(
                            workId: workId,
                            workTitle: title,
                            initialChapterId: initialChapterId,
                            session: session
                        )
                    }

                    let reader = model

                    navigator.aboutToGo = { [weak reader] in reader?.flushPosition() }

                    #if DEBUG
                        startSearchingIfAsked()
                    #endif
                }
                .task { await model?.loadIfNeeded() }
                // Where the reader stopped is worth writing the moment they stop: an app on its way to
                // the background will not run a task that is still waiting.
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { model?.flushPosition() }
                }
                .onDisappear {
                    navigator.aboutToGo = nil
                    model?.flushPosition()
                }
            }
        }

        @ViewBuilder
        private func page(_ model: Model) -> some View {
            @Bindable var model = model

            pageArea($model)
                .overlay {
                    if model.isOpening {
                        openingCard(model.paginationProgress)
                    } else if let message = model.errorMessage, model.layout == nil {
                        ContentUnavailableView("Couldn’t open", systemImage: "book.closed", description: Text(message))
                    }
                }
        }

        /// The one thing the reader sees between tapping a book and reading it.
        ///
        /// Fetching the chapter and measuring the book are one wait to whoever is waiting, so they get
        /// one card: the bar runs on its own until the measuring can say how far along it is.
        ///
        /// On a card, because the first page it covers is the title page and a bar drawn straight onto
        /// the cover is unreadable. The page's own colours rather than a material, which would follow
        /// the system's light or dark instead of the theme the reader chose.
        private func openingCard(_ progress: Double?) -> some View {
            VStack(spacing: 12) {
                Text("Setting the pages…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(settings.theme.foreground)

                ProgressBar(value: progress, tint: settings.theme.foreground)

                Text(progress?.formatted(.percent.precision(.fractionLength(0))) ?? " ")
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
            .accessibilityValue(progress?.formatted(.percent.precision(.fractionLength(0))) ?? "")
        }

        @ViewBuilder
        private func pageArea(_ model: Bindable<Model>) -> some View {
            let value = model.wrappedValue

            PageTurnView(
                pageCount: value.sheetCount,
                index: model.currentSheet,
                hasPageBefore: value.hasPageBefore,
                hasPageAfter: value.hasPageAfter,
                onPastEnd: value.goToNextChapter,
                onPastStart: value.goToPreviousChapter,
                onPageTap: { point in follow(point, in: value) },
                onPickOut: { start, finish in pickOut(from: start, to: finish, in: value) },
                onPickedOut: { withAnimation(CalloutMotion.showing) { picked = value.picked } },
                isCovered: value.picked != nil || note != nil || isPageCovered,
                onMiddleTap: toggleChrome,
                onTurnStarted: {
                    hideChrome()
                    value.noteTurn()
                },
                readsRightToLeft: value.readsRightToLeft,
                advancesOnLeftTap: settings.advancesOnLeftTap,
                page: { sheet in sheetContent(value, at: sheet) }
            )
            .accessibilityIdentifier("reader.page")
            .ignoresSafeArea()
            // Over the page and in its coordinates, so the controls and the running head are placed
            // from the same edge of the screen.
            .overlay(alignment: band.alignment) { controls }
            // In the page's own coordinates, so it stands clear of the corner whatever the page does
            // with the safe area.
            .overlay(alignment: .bottomLeading) { wayBack(model.wrappedValue) }
            .accessibilityActions { noteActions(value) }
            .callout(
                over: anchor(of: note?.rect),
                item: $note,
                ground: Callout<EmptyView>.surface(over: settings.theme.background, with: settings.theme.foreground),
                coversSafeArea: true
            ) { noteCard($0.note) }
            .callout(
                over: anchor(of: pickedBox(picked)),
                item: pickedBinding,
                ground: Callout<EmptyView>.surface(over: settings.theme.background, with: settings.theme.foreground),
                coversSafeArea: true,
                content: { chosen in pickedMenu(chosen) }
            )
            .modifier(ReaderFeedback(picked: value.picked?.id, showing: picked != nil, note: note?.id))
            .sheet(item: $lookedUp) { DictionaryView(term: $0.term) }
            .translationPresentation(isPresented: $isTranslating, text: translating)
            // The window, not the layout: a page ignores the safe area, so the size its parent hands
            // it is not the size it draws at, and a toolbar coming and going would move it besides.
            .onGeometryChange(for: CGSize.self, of: { $0.size }, action: { _ in applyWindowMetrics() })
            .onVerticalBarEdge { edge in
                barEdge = edge
                applyWindowMetrics()
            }
            .onChange(of: layoutContext, initial: true) {
                value.apply(context: layoutContext, columns: spread.columns)
            }
        }

        /// What an aside is hung over, in the page's own coordinates.
        ///
        /// No correction: the aside is told the page reaches past the safe area, so it counts from the
        /// same corner the page's own taps and boxes do. Correcting each place by hand is what put
        /// every aside a notch's depth away from what it pointed at.
        private func anchor(of rect: CGRect?) -> CGRect { rect ?? .zero }

        /// Everything the reader picked out, as one box for an aside to stand clear of, in the sheet's
        /// coordinates rather than in those of the page the words came off.
        private func pickedBox(_ chosen: Model.PickedText?) -> CGRect? {
            guard let chosen, let bounds = CalloutPlacement.bounds(around: chosen.rects) else { return nil }

            return spread.onSheet(bounds, column: column(of: chosen.page))
        }

        /// Which column of the spread a page stands in.
        private func column(of page: Int) -> Int {
            model?.pagesOnScreen.firstIndex(of: page) ?? 0
        }

        /// Opens a note where one was tapped. Reports whether there was one, since the page turns if not.
        /// Drawn text is invisible to VoiceOver, so a marker cannot be touched. The page offers the
        /// notes it stands on as actions of its own instead.
        @ViewBuilder
        private func noteActions(_ model: Model) -> some View {
            ForEach(model.notesOnPage) { found in
                Button("Note \(found.marker)") {
                    let middle = CGPoint(x: sheetSize.width / 2, y: sheetSize.height / 2)

                    note = .init(note: found, rect: CGRect(origin: middle, size: .zero))
                }
            }
        }

        /// A tap on the page: a note's marker first, since it is the smaller target, then a link.
        ///
        /// The point arrives in the sheet's own coordinates, so it is carried onto whichever page of the
        /// spread it landed on before anything is asked about it.
        private func follow(_ point: CGPoint, in model: Model) -> Bool {
            let spread = spread
            let column = spread.column(containing: point.x)
            let index = model.page(inColumn: column)
            let onPage = spread.onPage(point, column: column)

            if show(model.note(at: onPage, onPage: index), in: column) { return true }

            guard let target = model.link(at: onPage, onPage: index) else { return false }

            model.follow(target)
            offerTheWayBack()
            return true
        }

        /// Words drawn out of one page of the spread, the page settled by where the finger went down.
        private func pickOut(from start: CGPoint, to finish: CGPoint, in model: Model) {
            let spread = spread
            let column = spread.column(containing: start.x)

            model.pickOut(
                from: spread.onPage(start, column: column),
                to: spread.onPage(finish, column: column),
                onPage: model.page(inColumn: column)
            )
        }

        /// The way back stands for half a minute and then fades, since a reader who was going to take
        /// it has taken it by then, and one who read on should not be read to over.
        private func offerTheWayBack() {
            fading = false
            wayBackFade?.cancel()
            wayBackFade = Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.wayBackStands))

                guard !Task.isCancelled else { return }

                withAnimation(.easeInOut(duration: Self.wayBackFade)) { fading = true }
                try? await Task.sleep(for: .seconds(Self.wayBackFade))

                guard !Task.isCancelled else { return }

                model?.forgetTheWayBack()
            }
        }

        @ViewBuilder
        private func wayBack(_ model: Model) -> some View {
            if model.wayBack != nil, !isSearching {
                GlassRow {
                    Button("Back to where you were", systemImage: "arrow.uturn.backward") {
                        wayBackFade?.cancel()
                        model.goBack()
                    }
                    .accessibilityIdentifier("reader.wayBack")
                    .accessibilityHint("Returns to the page the link was followed from")
                }
                .padding(.leading, safeArea.leading + Design.Space.extraLarge)
                .padding(
                    .bottom,
                    Self.controlsBottom(
                        over: spread.pageSafeArea.bottom,
                        headSize: runningHeadSize,
                        band: layoutContext.runningHeadBand
                    )
                )
                // Counted from the foot of the screen, as the page number is: an overlay is given the
                // safe area back even where the view under it turned it down.
                .ignoresSafeArea()
                .opacity(fading ? 0 : 1)
                .transition(.opacity)
            }
        }

        /// The bar for finding a passage, standing on the line the page number is set on.
        @ViewBuilder
        private func searching(_ model: Model) -> some View {
            if isSearching {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    SearchBar(model: model, query: $query, focused: $searchFocused, onClose: stopSearching)
                        .padding(.horizontal, safeArea.leading + Design.Space.extraLarge)
                        // Whichever stands deeper, the device's own band or the keyboard: the bar keeps
                        // to the line the page number is set on until a keyboard reaches past it, and
                        // then to the keyboard. Adding them instead counts the band twice, since the
                        // keyboard is measured from the foot of the window and covers the band already.
                        .padding(
                            .bottom,
                            max(spread.pageSafeArea.bottom + Self.headInset, keyboardCover + Design.Space.medium)
                        )
                }
                // The layer is the window, as every other piece of the reader's chrome is. A bar that
                // kept the safe area would be moved by the band and by the measurement of it both.
                .ignoresSafeArea()
                .keyboardCover($keyboardCover)
                .transition(.opacity)
            }
        }

        #if DEBUG
            /// `-at-ui-test-find YES` opens with the bar for finding a passage already up and the
            /// keyboard with it, so where it stands can be looked at without walking the menu first.
            private func startSearchingIfAsked() {
                guard UserDefaults.standard.bool(forKey: "at-ui-test-find") else { return }

                startSearching()
            }
        #endif

        private func startSearching() {
            query = model?.findQuery ?? ""
            withAnimation(.easeInOut(duration: Self.chromeFade)) { isSearching = true }
            searchFocused = true
        }

        private func stopSearching() {
            searchFocused = false
            withAnimation(.easeInOut(duration: Self.chromeFade)) { isSearching = false }
            model?.stopFinding()
        }

        /// How long the way back stands before it starts to go.
        private static let wayBackStands: Double = 30
        private static let wayBackFade: Double = 1.5

        private func show(_ found: Model.TappedNote?, in column: Int) -> Bool {
            guard let found else { return false }

            let carried = Model.TappedNote(note: found.note, rect: spread.onSheet(found.rect, column: column))

            withAnimation(CalloutMotion.showing) { note = carried }
            return true
        }

        /// Putting the menu away takes the paint under the words with it.
        private var pickedBinding: Binding<Model.PickedText?> {
            Binding(
                get: { picked },
                set: { chosen in
                    withAnimation(chosen == nil ? CalloutMotion.hiding : CalloutMotion.showing) {
                        picked = chosen
                    }

                    if chosen == nil { model?.clearPicked() }
                }
            )
        }

        private func clearPicked() {
            withAnimation(CalloutMotion.hiding) { picked = nil }
            model?.clearPicked()
        }

        /// What can be done with the words the reader drew a finger across.
        private func pickedMenu(_ chosen: Model.PickedText) -> some View {
            Callout(
                foreground: settings.theme.foreground,
                background: settings.theme.background,
                onClose: clearPicked,
                content: {
                    VStack(alignment: .leading, spacing: Design.Space.small) {
                        action("Look up", systemImage: "character.book.closed") {
                            lookedUp = LookedUpTerm(term: chosen.selection.text)
                        }

                        action("Translate", systemImage: "translate") {
                            translating = chosen.selection.text
                            isTranslating = true
                        }

                        action("Copy", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = chosen.selection.text
                        }

                        action("Add bookmark", systemImage: "bookmark") {
                            model?.bookmarkPicked()
                        }
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
                title: note.marker,
                foreground: settings.theme.foreground,
                background: settings.theme.background,
                onClose: { withAnimation(CalloutMotion.hiding) { self.note = nil } },
                content: { BookTextView(text: note.text, style: noteStyle, width: Design.Size.calloutText) }
            )
            .accessibilityIdentifier("reader.note")
            .accessibilityLabel("Note \(note.marker)")
        }

        /// A note is the book's own text, so it is set the way the page is and only a shade smaller,
        /// being an aside rather than the text itself.
        private var noteStyle: ChapterTextStyle {
            var style = settings.textStyle

            style.fontSize *= Self.noteScale
            style.lineSpacing *= Self.noteScale
            // A note is one aside standing on its own, with nothing above it to be told apart from.
            style.indentsParagraphs = false
            return style
        }

        private static let noteScale = 0.88

        /// One sheet, which is what a turn moves: a single page, or two standing side by side with the
        /// binding between them.
        ///
        /// The pages are placed rather than stacked in a row, since each one is measured against its own
        /// width and a spread's outer margins are whatever the sheet had over.
        @ViewBuilder
        private func sheetContent(_ model: Model, at sheet: Int) -> some View {
            let spread = spread
            let alone = spread.columns == 1

            settings.theme.background
                // Laid over, not stacked: a page as tall as the window would push the sheet off its corner.
                .overlay(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(model.pages(onSheet: sheet).enumerated()), id: \.offset) { column, index in
                            pageContent(model, at: index, titled: alone)
                                .frame(width: spread.pageSize.width, height: spread.pageSize.height)
                                .offset(x: spread.origin(ofColumn: column))
                        }
                    }
                }
                // One title over the spread rather than the same words twice, set in the middle of the
                // sheet the way a printed book sets it across the opening.
                .overlay(alignment: .top) {
                    if !alone, model.showsTitle(onSheet: sheet) {
                        runningHead(model.bookTitle, edge: .head)
                    }
                }
        }

        /// One page, drawn edge to edge: the text, the book's title above it and the page number below.
        /// Both run with the page rather than sitting in chrome around it, so a turn moves everything.
        @ViewBuilder
        private func pageContent(_ model: Model, at index: Int, titled: Bool) -> some View {
            let footer = model.caption(at: index, expanded: !isChromeHidden)
            let isCurrent = index == model.currentPage

            switch model.page(at: index) {
                case .title:
                    BookTitlePageView(
                        title: model.bookTitle,
                        author: model.book?.authorLine ?? "",
                        seriesTitle: model.book?.seriesTitle,
                        coverURL: model.book?.coverURL,
                        style: settings.textStyle,
                        margins: settings.settledMargins,
                        safeArea: spread.pageSafeArea
                    )
                    .background(settings.theme.background)
                    .overlay(alignment: .bottom) { runningHead(footer, edge: .foot, isCaption: isCurrent) }
                case let .text(pieces):
                    // Two pieces where a chapter starts on the page the one before it ended on. Each
                    // draws only its own lines, in its own place on the page.
                    ZStack {
                        ForEach(pieces) { piece in
                            ChapterPageView(layout: piece.layout, pageIndex: piece.page)
                        }

                        if model.picked?.page == index { picking(model) }

                        standingOn(model.foundRects(onPage: index))

                        GutterMarks(
                            marks: model.marks(onPage: index),
                            textEdge: layoutContext.textRect.maxX,
                            pageWidth: spread.pageSize.width,
                            ink: settings.theme.foreground.opacity(Self.markInk)
                        )
                    }
                    .background(settings.theme.background)
                    .overlay(alignment: .top) { if titled { runningHead(model.bookTitle, edge: .head) } }
                    .overlay(alignment: .bottom) { runningHead(footer, edge: .foot, isCaption: isCurrent) }
                case .blank:
                    settings.theme.background
            }
        }

        /// A shade off the text's own ink: the mark is the reader's, not the book's.
        private static let markInk: CGFloat = 0.55

        /// What the reader has drawn a finger across, painted under the words rather than over them.
        @ViewBuilder
        private func picking(_ model: Model) -> some View {
            if let picked = model.picked {
                ForEach(Array(picked.rects.enumerated()), id: \.offset) { _, painted in
                    RoundedRectangle(cornerRadius: Design.Radius.small)
                        .fill(Design.Surface.picked(settings.theme.foreground))
                        .frame(width: painted.width, height: painted.height)
                        .position(x: painted.midX, y: painted.midY)
                }
                .accessibilityHidden(true)
            }
        }

        /// The words the reader was taken to by searching, painted under them as a selection is: the
        /// page is drawn, so nothing on it can be given a colour of its own.
        private func standingOn(_ rects: [CGRect]) -> some View {
            ForEach(Array(rects.enumerated()), id: \.offset) { _, painted in
                RoundedRectangle(cornerRadius: Design.Radius.small)
                    .fill(Design.Surface.picked(settings.theme.foreground))
                    .frame(width: painted.width, height: painted.height)
                    .position(x: painted.midX, y: painted.midY)
            }
            .accessibilityHidden(true)
        }

        /// The book title above the text, or the page number below it.
        @ViewBuilder
        private func runningHead(_ text: String?, edge: RunningHead.Edge, isCaption: Bool = false) -> some View {
            if let text, !text.isEmpty {
                RunningHead(
                    text: text,
                    edge: edge,
                    size: edge == .foot ? runningHeadSize * Self.captionScale : runningHeadSize,
                    // With the controls away this is the only thing naming the page, so it takes a
                    // little more ink; with them up it steps back and lets them carry it.
                    ink: settings.theme.foreground.opacity(isChromeHidden ? 0.6 : 0.4),
                    margins: settings.settledMargins,
                    deviceInset: edge == .head ? spread.pageSafeArea.top : spread.pageSafeArea.bottom,
                    band: layoutContext.runningHeadBand
                )
                // Only the page the reader is on names itself, so a turn never puts two of these on
                // screen under the same identifier.
                .accessibilityIdentifier(isCaption ? "reader.caption" : "")
                .accessibilityHidden(!isCaption)
            }
        }

        /// Whether the status bar goes away with the controls: only where that moves nothing, under a
        /// notch or in a vertical bar the page makes no room for. An iPad's status bar is its whole top
        /// inset, so there it stays.
        private var hidesStatusBar: Bool {
            isChromeHidden && (safeArea.top >= Self.deviceBandDepth || band.isDownASide)
        }

        /// Deeper than any status bar, shallower than any notch.
        private static let deviceBandDepth: CGFloat = 40

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
            let spread = spread

            return ChapterLayout.Context(
                style: settings.textStyle,
                margins: settings.settledMargins,
                pageSize: spread.pageSize,
                safeArea: spread.pageSafeArea
            )
        }

        /// Takes the page's size and the device's own insets from the window, which keeps both whatever
        /// chrome is on screen.
        private func applyWindowMetrics() {
            let scene = UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene

            guard let window = scene?.keyWindow else { return }

            let insets = window.safeAreaInsets
            let live = EdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)

            safeArea = band.pageInsets(from: live)
            sheetSize = window.bounds.size
        }

        /// Where the system stands its own bar, and so where the controls stand.
        private var band: DeviceBand { DeviceBand(barEdge: barEdge) }

        /// How the sheet is divided: one page, or two with the binding between them.
        private var spread: PageSpread {
            PageSpread(
                sheet: sheetSize,
                safeArea: safeArea,
                margins: settings.settledMargins,
                textSize: settings.fontSize
            )
        }

        /// How long the controls take to fade in or out.
        private static let chromeFade: Double = 0.25

        /// The page number sits a little smaller than the book's title above it.
        private static let captionScale: CGFloat = 0.9

        /// The reader's own controls, standing on the line the running head is set on.
        ///
        /// Drawn here rather than handed to a bar: a bar centres what it is given on its own height and
        /// reads no offset asking for anything else.
        /// The controls, built only while they are up.
        ///
        /// Faded out is not gone: a row under glass goes on being read out and found by name however
        /// little of it is drawn, so a reader that only faded them would offer VoiceOver controls that
        /// are not there, and a test would find buttons nobody can see.
        @ViewBuilder
        private var controls: some View {
            if !isChromeHidden { chrome.transition(.opacity) }
        }

        /// The controls, set out along whichever edge the device keeps its own band on.
        @ViewBuilder
        private var chrome: some View {
            if band.isDownASide { downTheSide } else { acrossTheTop }
        }

        private var acrossTheTop: some View {
            HStack(alignment: .top, spacing: Design.Space.large) {
                GlassRow { wayOut }

                Spacer(minLength: 0)

                GlassRow { marking }

                GlassRow { more }
            }
            // Clear of whatever the device keeps down either side, which on a phone turned on its side
            // is the sensor housing the close button was sitting under.
            .padding(.leading, safeArea.leading + Design.Space.extraLarge)
            .padding(.trailing, safeArea.trailing + Design.Space.extraLarge)
            .padding(
                .top,
                Self.controlsTop(
                    under: spread.pageSafeArea.top,
                    headSize: runningHeadSize,
                    band: layoutContext.runningHeadBand
                )
            )
            // Counted from the top of the screen, as the running head is: an overlay is given the safe
            // area back even where the view under it turned it down.
            .ignoresSafeArea()
        }

        /// Down the column a folding screen keeps its vertical bar in, where the system stands its own
        /// buttons, and over the edge of a page that is set to the whole width.
        private var downTheSide: some View {
            VStack(spacing: Design.Space.large) {
                GlassRow(.down) { wayOut }

                Spacer(minLength: 0)

                GlassRow(.down) { marking }

                GlassRow(.down) { more }
            }
            .padding(.top, Self.statusColumnDepth)
            .padding([ .bottom, band == .leading ? .leading : .trailing ], Design.Space.huge)
            // As wide as it is offered, or turning the safe area down reaches no further than the page.
            .frame(maxWidth: .infinity, alignment: band.alignment)
            .ignoresSafeArea()
        }

        /// How far down its column the system's status items reach, which no inset reports.
        private static let statusColumnDepth: CGFloat = 120

        /// The way out, since a presented screen has no back button of its own. The glyph is the
        /// gesture: a drag down the page does the same thing.
        @ViewBuilder
        private var wayOut: some View {
            Button("Close", systemImage: "chevron.down") { dismiss() }
                .accessibilityIdentifier("reader.close")
                .accessibilityHint("Closes the book")
        }

        /// Whether the book is marked here, and whether it is being read off the device.
        ///
        /// Under a pane of its own. What it does happens on the page behind it, where the menu beside it
        /// opens something over the page, and one glass holding both read as a bar of odds and ends.
        @ViewBuilder
        private var marking: some View {
            if model?.isOffline == true {
                Image(systemName: "wifi.slash")
                    .font(.system(size: Design.Size.glyph(in: Design.Size.touch)))
                    .foregroundStyle(.secondary)
                    .frame(width: Design.Size.touch, height: Design.Size.touch)
                    .accessibilityLabel("Reading from this device")
            }

            let isMarked = model?.isPageBookmarked == true

            Button(
                isMarked ? "Remove bookmark" : "Add bookmark",
                systemImage: isMarked ? "bookmark.fill" : "bookmark"
            ) {
                model?.toggleBookmark()
            }
            .accessibilityHint("Marks the page, or clears the marks on it")
            .disabled(model?.canBookmarkPage != true)
        }

        /// Everything that opens something of its own, under one glyph.
        ///
        /// The bar is read over a page, so only what is wanted while reading stands on it: the way out,
        /// whether the book is marked here, and this. The rest is a tap further away and the page keeps
        /// the room.
        ///
        /// The two forms hang here rather than on the rows in the menu. A menu is gone by the moment
        /// its row acts, and a popover hung on something gone has nothing left to point at, so it
        /// points at this instead, which is what the reader touched.
        private var more: some View {
            Menu {
                Button("Contents", systemImage: "list.bullet") { isShowingContents = true }

                Button("Find", systemImage: "magnifyingglass") { startSearching() }

                Button("Appearance", systemImage: "textformat.size") { isShowingSettings = true }

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
            .popover(isPresented: $isShowingContents) {
                if let model {
                    ContentsSheet(model: model, isPresented: $isShowingContents)
                }
            }
            .popover(isPresented: $isShowingSettings) { SettingsSheet() }
        }

        /// Where the controls start, so that the middle of them lands on the middle of the line the
        /// running head is set on. The head sits its own inset below the safe area.
        static func controlsTop(under safeAreaTop: CGFloat, headSize: CGFloat, band: CGFloat) -> CGFloat {
            safeAreaTop + RunningHead.air(band, headSize) + (headLine(headSize) - Design.Size.touch) / 2
        }

        /// Where the way back stands, so its middle lands on the middle of the line the page number is
        /// set on. The number sits its own inset above the safe area, as the running head sits below it.
        static func controlsBottom(over safeAreaBottom: CGFloat, headSize: CGFloat, band: CGFloat) -> CGFloat {
            safeAreaBottom + RunningHead.air(band, headSize * captionScale)
                + (headLine(headSize * captionScale) - Design.Size.touch) / 2
        }

        /// The line a running head of this size is set on, which is taller than the type itself.
        static func headLine(_ headSize: CGFloat) -> CGFloat { RunningHead.line(headSize) }

        /// What the running head keeps between itself and the safe area.
        static let headInset: CGFloat = RunningHead.inset

        #if DEBUG
            /// The page, what it was set with and a picture of it, zipped and offered to share.
            private func collectReport() {
                guard let model else { return }

                // The bar would otherwise stand in the picture, and the page is what is being asked about.
                isChromeHidden = true

                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))

                    let markup = await model.chapterMarkup()

                    guard
                        let url = try? DebugReport.make(
                            pageText: model.pageText,
                            settings: settingsReport,
                            lines: linesReport(model),
                            markup: markup
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
                    runningHeadBand: \(layoutContext.runningHeadBand)
                    rulesVersion: \(ChapterLayout.rulesVersion)
                    typographyVersion: \(Typography.version)
                    fingerprint: \(context.fingerprint)
                    chapter: \(model?.currentChapterId.map(String.init) ?? "nil")
                    page: \((model?.currentPage ?? 0) + 1) of \(model?.pageCount ?? 0)
                    """
            }
        #endif
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
                    model.open(chapterId: mark.chapterId, anchor: .offset(mark.startOffset))
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

/// What the page answers with a tick as well as a picture.
///
/// The first word under the finger, each new one taken in after it, and the moment an aside arrives.
/// Kept apart from the page's own body, which has enough to say already.
private struct ReaderFeedback: ViewModifier {
    let picked: String?
    let showing: Bool
    let note: String?

    func body(content: Content) -> some View {
        content
            .sensoryFeedback(trigger: picked) { before, now in
                guard now != nil else { return nil }

                // Firmer for the first word, since that is the moment picking began; lighter for each
                // one after it, which is the tick a picker gives as it passes a value.
                return before == nil ? .impact(weight: .medium) : .selection
            }
            .sensoryFeedback(trigger: showing) { _, shown in
                shown ? .impact(flexibility: .soft) : nil
            }
            .sensoryFeedback(trigger: note) { _, shown in
                shown != nil ? .impact(flexibility: .soft) : nil
            }
    }
}
