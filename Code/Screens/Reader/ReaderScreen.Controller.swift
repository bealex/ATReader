//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookRenderer
import DesignSystem
import SwiftUI
import UIKit

extension ReaderScreen {
    /// The reader: the book's sheets, laid out by hand, turned by a finger, with the controls laid over
    /// them the first time they are wanted.
    @MainActor
    final class Controller: UIViewController, PresentedScreenReporting {
        let model: Model
        var opening: BookOpening?
        var onArrived: (@MainActor () -> Void)?
        var onGoing: (@MainActor () -> Void)?
        var onGone: (@MainActor () -> Void)?
        private let stage: Stage
        private let settings: ReaderSettings
        private let navigator: Navigator?
        private let pictures: (any PagePictureLoading)?

        private let turner = PageTurner()
        private var sheetViews: [SheetView] = []
        /// Which sheet view stands at each step from the one in front of the reader.
        private var atStep: [Int: SheetView] = [:]
        private var failure: UIContentUnavailableView?
        private var chrome: ChromeLayer?
        private var loading: Task<Void, Never>?
        private var wayBackFade: Task<Void, Never>?
        private var appliedContext: (ChapterLayout.Context, Int)?
        private let pickFeedback = UISelectionFeedbackGenerator()
        private let firstPickFeedback = UIImpactFeedbackGenerator(style: .medium)
        private var pickedId: String?
        private var shownStatusBar: (Bool, UIStatusBarStyle)?
        /// Until the screen has arrived, the sheets either side are set out a frame or two after the one in
        /// front, so a book being opened never lays out three sheets in one frame.
        private var hasArrived = false

        init(
            workId: Int,
            title: String,
            initialChapterId: Int?,
            session: SessionStore,
            settings: ReaderSettings,
            navigator: Navigator?,
            pictures: (any PagePictureLoading)?
        ) {
            model = Model(workId: workId, workTitle: title, initialChapterId: initialChapterId, session: session)
            stage = Stage(settings: settings)
            self.settings = settings
            self.navigator = navigator
            self.pictures = pictures
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidLoad() {
            super.viewDidLoad()

            turner.frame = view.bounds
            turner.autoresizingMask = [ .flexibleWidth, .flexibleHeight ]
            view.addSubview(turner)

            for _ in 0 ..< Self.sheetsHeld {
                sheetViews.append(SheetView(model: model, stage: stage, pictures: pictures))
            }

            turner.sheet = { [weak self] step in self?.atStep[step] }
            turner.onForward = { [weak self] in self?.turned { $0.turnForward() } }
            turner.onBack = { [weak self] in self?.turned { $0.turnBack() } }
            turner.onPageTap = { [weak self] point in self?.follow(point) ?? false }
            turner.onPickOut = { [weak self] start, finish in self?.pickOut(from: start, to: finish) }
            turner.onPickedOut = { [weak self] in self?.showPicked() }
            turner.onMiddleTap = { [weak self] in self?.toggleChrome() }
            turner.onTurnStarted = { [weak self] in self?.hideChrome() }

            let center = NotificationCenter.default

            // Where the reader stopped is worth writing the moment they stop: an app on its way to the
            // background will not run a task that is still waiting.
            for name in [ UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification ] {
                center.addObserver(self, selector: #selector(leaving), name: name, object: nil)
            }

            if #available(iOS 27.1, *) {
                registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) { (self: Self, _) in
                    self.applyWindowMetrics()
                }
            }

            loading = Task { [model] in await model.loadIfNeeded() }
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)

            // Written as the book starts closing rather than once it has closed: the shelf draws the mark
            // on a cover from the store, and the opening photographs that cover on its way home.
            // A shelf rebuilt as the book starts to close costs its first frames; a cover opening like a
            // book is photographed before that rebuild could land anyway.
            navigator?.aboutToGo = { [weak self] in self?.model.flushPosition(tellsLibrary: self?.opening == nil) }

            #if DEBUG
                if UserDefaults.standard.bool(forKey: "at-ui-test-find") { startSearching() }
            #endif
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            hasArrived = true
            onArrived?()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            onGoing?()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)

            navigator?.aboutToGo = nil
            model.flushPosition()

            if isBeingDismissed || isMovingFromParent { loading?.cancel() }

            onGone?()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            applyWindowMetrics()
        }

        override var prefersStatusBarHidden: Bool { stage.hidesStatusBar }
        override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }

        override var preferredStatusBarStyle: UIStatusBarStyle {
            settings.theme.colorScheme == .dark ? .lightContent : .darkContent
        }

        @objc
        private func leaving() { model.flushPosition() }

        // MARK: - Following the book

        override func updateProperties() {
            super.updateProperties()

            let theme = settings.theme
            let spread = stage.spread
            let context = stage.layoutContext

            view.backgroundColor = UIColor(theme.background)
            // The page's own light or dark, for everything shown over it too.
            overrideUserInterfaceStyle = theme.colorScheme == .dark ? .dark : .light
            followStatusBar()

            if stage.sheetSize != .zero, appliedContext.map({ $0.0 != context || $0.1 != spread.columns }) ?? true {
                appliedContext = (context, spread.columns)
                model.apply(context: context, columns: spread.columns)
            }

            turner.readsRightToLeft = model.readsRightToLeft
            turner.advancesOnLeftTap = settings.advancesOnLeftTap
            turner.isCovered = model.picked != nil || stage.isPageCovered || stage.hasAside
            turner.extraActions = noteActions()

            showFailure(model.currentSheet == nil ? model.errorMessage : nil)
            followPicking()
            placeSheets()
        }

        /// Fades the status bar with the controls, and tells it only when something it shows has changed.
        private func followStatusBar() {
            let wanted = (stage.hidesStatusBar, preferredStatusBarStyle)

            guard shownStatusBar.map({ $0 != wanted }) ?? true else { return }

            shownStatusBar = wanted
            UIView.animate(withDuration: Stage.chromeFade) { self.setNeedsStatusBarAppearanceUpdate() }
        }

        /// Hands each step the view for its sheet, keeping a view with the sheet it already shows so a
        /// turn never builds again what is already on screen.
        private func placeSheets() {
            // A turn onto a sheet still being cut has already put that sheet in front, blank; the one it
            // left doesn't come back while the new one fills in.
            let wanted = (-1 ... 1).map { step in
                (step, step == 0 && model.isWaitingForSheet ? nil : model.sheet(at: step))
            }
            var free = sheetViews
            var placed: [Int: SheetView] = [:]

            for (step, sheet) in wanted {
                // A sheet still being cut is kept by the view already standing blank for it.
                guard let index = free.firstIndex(where: { $0.sheet == sheet }) else { continue }

                placed[step] = free.remove(at: index)
            }

            for (step, _) in wanted where placed[step] == nil { placed[step] = free.removeFirst() }

            atStep = placed

            for (step, sheet) in wanted {
                guard let view = placed[step] else { continue }

                if step == 0 || hasArrived {
                    view.show(sheet, isCurrent: step == 0)
                } else {
                    show(sheet, on: view, at: step)
                }
            }

            turner.hasSheetBefore = model.canTurnBack
            turner.hasSheetAfter = model.canTurnForward
            turner.reload()
        }

        /// The view standing `step` sheets from the one in front of the reader, once it holds a sheet.
        func turnerSheet(at step: Int) -> UIView? { atStep[step].flatMap { $0.sheet == nil ? nil : $0 } }

        /// Shows a sheet either side a frame after the one in front, the one before first since the opening
        /// shows it on the back of the leaf; a view handed to another step meanwhile is left alone.
        private func show(_ sheet: Model.Sheet?, on view: SheetView, at step: Int) {
            let frames = step < 0 ? 1 : 2

            Task { [weak self, weak view] in
                try? await Task.sleep(for: Self.arrivingFrame * frames)

                guard let self, let view, self.atStep[step] === view else { return }

                view.show(sheet, isCurrent: false)
            }
        }

        /// A frame at 120 Hz.
        private static let arrivingFrame = Duration.microseconds(8_333)

        /// A turn has landed: the book moves on, and the sheets move with it in the same frame.
        private func turned(_ move: (Model) -> Void) {
            move(model)
            placeSheets()
        }

        /// Takes the page's size and the device's own insets from the window, which keeps both whatever
        /// chrome is on screen.
        private func applyWindowMetrics() {
            guard let window = view.window else { return }

            let insets = window.safeAreaInsets
            let live = EdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
            var band = DeviceBand.top

            if #available(iOS 27.1, *) {
                switch traitCollection.verticalBarEdge {
                    case .leading: band = .leading
                    case .trailing: band = .trailing
                    default: band = .top
                }
            }

            let safeArea = band.pageInsets(from: live)

            if stage.band != band { stage.band = band }
            if stage.safeArea != safeArea { stage.safeArea = safeArea }
            if stage.sheetSize != window.bounds.size { stage.sheetSize = window.bounds.size }
        }

        private func showFailure(_ message: String?) {
            guard
                let message
            else {
                failure?.removeFromSuperview()
                failure = nil
                return
            }

            var configuration = UIContentUnavailableConfiguration.empty()

            configuration.image = UIImage(systemName: "book.closed")
            configuration.text = String(localized: "Couldn’t open")
            configuration.secondaryText = message

            let shown = failure ?? UIContentUnavailableView(configuration: configuration)

            shown.configuration = configuration
            shown.frame = view.bounds
            shown.autoresizingMask = [ .flexibleWidth, .flexibleHeight ]

            if failure == nil { view.insertSubview(shown, aboveSubview: turner) }

            failure = shown
        }

        // MARK: - Touches on the page

        /// A tap on the page: a note's marker first, since it is the smaller target, then a link.
        ///
        /// The point arrives in the sheet's own coordinates, and is carried onto whichever page of the
        /// spread it landed on before anything is asked about it.
        private func follow(_ point: CGPoint) -> Bool {
            let spread = stage.spread
            let column = spread.column(containing: point.x)
            let onPage = spread.onPage(point, column: column)

            guard let page = model.page(inColumn: column) else { return false }

            if let found = model.note(at: onPage, on: page) {
                show(Model.TappedNote(note: found.note, rect: spread.onSheet(found.rect, column: column)))
                return true
            }

            guard let target = model.link(at: onPage, on: page) else { return false }

            model.follow(target)
            offerTheWayBack()
            return true
        }

        private func show(_ note: Model.TappedNote) {
            buildChrome()
            withAnimation(CalloutMotion.showing) { stage.note = note }
        }

        /// Words drawn out of one page of the spread, the page settled by where the finger went down.
        private func pickOut(from start: CGPoint, to finish: CGPoint) {
            let spread = stage.spread
            let column = spread.column(containing: start.x)

            guard let page = model.page(inColumn: column) else { return }

            model.pickOut(
                from: spread.onPage(start, column: column),
                to: spread.onPage(finish, column: column),
                on: page
            )
        }

        private func showPicked() {
            guard let picked = model.picked else { return }

            buildChrome()
            withAnimation(CalloutMotion.showing) { stage.picked = picked }
        }

        /// A firmer tick for the first word, since that is the moment picking began, and a lighter one
        /// for each word taken in after it.
        private func followPicking() {
            let id = model.picked?.id

            defer { pickedId = id }

            guard id != pickedId, id != nil else { return }

            if pickedId == nil { firstPickFeedback.impactOccurred() } else { pickFeedback.selectionChanged() }
        }

        /// Drawn text is invisible to VoiceOver, so a marker cannot be touched: the page offers the notes
        /// it stands on as actions instead.
        private func noteActions() -> [UIAccessibilityCustomAction] {
            model.notesOnPage.map { found in
                UIAccessibilityCustomAction(name: String(localized: "Note \(found.marker)")) { [weak self] _ in
                    guard let self else { return false }

                    let middle = CGPoint(x: stage.sheetSize.width / 2, y: stage.sheetSize.height / 2)

                    show(Model.TappedNote(note: found, rect: CGRect(origin: middle, size: .zero)))
                    return true
                }
            }
        }

        // MARK: - The controls

        private func toggleChrome() {
            buildChrome()
            withAnimation(.easeInOut(duration: Stage.chromeFade)) { stage.isChromeHidden.toggle() }
        }

        /// Turning a page is reading, so the controls get out of the way.
        private func hideChrome() {
            guard !stage.isChromeHidden else { return }

            withAnimation(.easeInOut(duration: Stage.chromeFade)) { stage.isChromeHidden = true }
        }

        private func startSearching() {
            buildChrome()
            stage.isSearching = true
        }

        /// The way back stands for half a minute and then fades: a reader who was going to take it has
        /// taken it by then, and one who read on should not be read to over.
        private func offerTheWayBack() {
            buildChrome()
            stage.fading = false
            wayBackFade?.cancel()
            wayBackFade = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.wayBackStands))

                guard !Task.isCancelled, let self else { return }

                withAnimation(.easeInOut(duration: Self.wayBackFade)) { self.stage.fading = true }
                try? await Task.sleep(for: .seconds(Self.wayBackFade))

                guard !Task.isCancelled else { return }

                model.forgetTheWayBack()
            }
        }

        /// Lays the controls over the page, the first time anything of theirs is wanted.
        ///
        /// Laid out at once and in the same state they were, so whatever is asked of them next arrives
        /// as a change and animates.
        private func buildChrome() {
            guard chrome == nil else { return }

            let root = Chrome(model: model, stage: stage, close: { [weak self] in self?.dismiss(animated: true) })
                .environment(settings)
            let host = UIHostingController(rootView: root)
            let layer = ChromeLayer(stage: stage)

            host.view.backgroundColor = .clear
            layer.frame = view.bounds
            layer.autoresizingMask = [ .flexibleWidth, .flexibleHeight ]
            host.view.frame = layer.bounds
            host.view.autoresizingMask = [ .flexibleWidth, .flexibleHeight ]

            addChild(host)
            layer.addSubview(host.view)
            view.addSubview(layer)
            host.didMove(toParent: self)
            host.view.layoutIfNeeded()
            chrome = layer
        }

        private static let sheetsHeld = 3
        private static let wayBackStands: Double = 30
        private static let wayBackFade: Double = 1.5
    }

    /// Holds the controls, and passes every touch they don't stand under on to the page.
    ///
    /// SwiftUI answers a hit test with its hosting view wherever the touch lands, drawn or not, so what
    /// is under a control is told by the places the controls report.
    private final class ChromeLayer: UIView {
        private let stage: Stage

        init(stage: Stage) {
            self.stage = stage
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard let hit = super.hitTest(point, with: event) else { return nil }
            guard !stage.hasAside else { return hit }

            let inWindow = convert(point, to: nil)

            return stage.touchAreas.values.contains { $0.contains(inWindow) } ? hit : nil
        }
    }
}

extension ReaderScreen.Controller: OpensOntoPage {
    var readShare: Double? { model.currentSheet == nil ? nil : model.bookProgress }

    var isPageBeforeReady: Bool { model.canTurnBack && (turnerSheet(at: -1)?.bounds.width ?? 0) > 0 }

    func facePageBefore() -> (contents: Any, frame: CGRect)? {
        guard let before = turnerSheet(at: -1) as? ReaderScreen.SheetView else { return nil }

        before.updatePropertiesIfNeeded()
        before.layoutIfNeeded()

        return before.drawnPage
    }

    func drawPageBefore(in context: CGContext) {
        guard let before = turnerSheet(at: -1) else { return }

        before.updatePropertiesIfNeeded()
        before.layoutIfNeeded()

        // The page turner keeps it at no opacity until a turn brings it in.
        let alpha = before.alpha

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        before.alpha = 1
        defer {
            before.alpha = alpha
            CATransaction.commit()
        }

        before.layer.render(in: context)
    }
}
