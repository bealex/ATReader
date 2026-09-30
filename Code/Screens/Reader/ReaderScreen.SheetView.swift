//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookRenderer
import DesignSystem
import SwiftUI
import UIKit

extension ReaderScreen {
    /// One sheet, which is what a turn moves: a single page, or two standing side by side with the
    /// binding between them.
    ///
    /// Laid out by hand. Each page is measured against its own width, and a spread's outer margins are
    /// whatever the sheet had over.
    @MainActor
    final class SheetView: UIView {
        private let model: Model
        private let stage: Stage
        private let pictures: (any PagePictureLoading)?

        /// The sheet this stands for; nothing while the one wanted is still being cut.
        private(set) var sheet: Model.Sheet?
        /// Only the sheet the reader is on names its caption, so a turn never shows two of them.
        private(set) var isCurrent = false

        private var pageViews: [PageSlot] = []
        private let head = UILabel()
        private let caption = Caption()

        init(model: Model, stage: Stage, pictures: (any PagePictureLoading)?) {
            self.model = model
            self.stage = stage
            self.pictures = pictures
            super.init(frame: .zero)

            head.textAlignment = .center
            head.isAccessibilityElement = false
            addSubview(head)
            addSubview(caption)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func show(_ sheet: Model.Sheet?, isCurrent: Bool) {
            guard sheet != self.sheet || isCurrent != self.isCurrent else { return }

            self.sheet = sheet
            self.isCurrent = isCurrent
            setNeedsUpdateProperties()
        }

        override func updateProperties() {
            super.updateProperties()
            let theme = stage.settings.theme
            let spread = stage.spread
            let alone = spread.columns == 1
            let pages = sheet?.pages ?? []

            backgroundColor = UIColor(theme.background)

            while pageViews.count < pages.count {
                let slot = PageSlot(model: model, stage: stage, pictures: pictures)

                insertSubview(slot, at: pageViews.count)
                pageViews.append(slot)
            }

            for (column, slot) in pageViews.enumerated() {
                guard
                    column < pages.count
                else {
                    slot.isHidden = true
                    continue
                }

                slot.isHidden = false
                slot.show(pages[column], alone: alone, isCurrent: isCurrent)
                slot.frame = CGRect(
                    x: spread.origin(ofColumn: column),
                    y: 0,
                    width: spread.pageSize.width,
                    height: spread.pageSize.height
                )
            }

            // One title over a spread rather than the same words twice, set across the opening the way
            // a printed book sets it, and one caption under it.
            let showsHead = !alone && sheet?.showsTitle == true

            head.isHidden = !showsHead
            caption.isHidden = alone || sheet == nil

            if showsHead { stage.dressHead(head, text: model.bookTitle, in: bounds.width) }
            if !alone, let sheet {
                caption.apply(model: model, stage: stage, at: sheet.end, isCurrent: isCurrent, in: bounds)
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            followSize(of: self, laidOutAt: &laidOutSize)
        }

        private var laidOutSize: CGSize = .zero
    }

    /// One page of a sheet: its text or its title page, what is painted under the words, the marks in
    /// its gutter, and the running head and caption where it stands alone.
    @MainActor
    private final class PageSlot: UIView {
        private let model: Model
        private let stage: Stage
        private let pictures: (any PagePictureLoading)?

        private var page: BookPage?
        private var alone = true
        private var isCurrent = false

        private var texts: [ChapterPageView.PageView] = []
        private var titlePage: TitlePageView?
        private var missing: UIContentUnavailableView?
        private let painted = CALayer()
        private let marks = CALayer()
        private let head = UILabel()
        private let caption = Caption()

        init(model: Model, stage: Stage, pictures: (any PagePictureLoading)?) {
            self.model = model
            self.stage = stage
            self.pictures = pictures
            super.init(frame: .zero)

            layer.addSublayer(painted)
            layer.addSublayer(marks)
            head.textAlignment = .center
            head.isAccessibilityElement = false
            addSubview(head)
            addSubview(caption)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func show(_ page: BookPage, alone: Bool, isCurrent: Bool) {
            guard page != self.page || alone != self.alone || isCurrent != self.isCurrent else { return }

            self.page = page
            self.alone = alone
            self.isCurrent = isCurrent
            setNeedsUpdateProperties()
        }

        override func updateProperties() {
            super.updateProperties()
            guard let page else { return }

            let theme = stage.settings.theme

            backgroundColor = UIColor(theme.background)

            switch page.content {
                case .title: showTitle()
                case let .text(pieces): showText(pieces, on: page)
                case .missing: showMissing()
            }

            let showsHead = alone && page.isText

            head.isHidden = !showsHead
            caption.isHidden = !alone

            if showsHead { stage.dressHead(head, text: model.bookTitle, in: bounds.width) }
            if alone { caption.apply(model: model, stage: stage, at: page.end, isCurrent: isCurrent, in: bounds) }

            bringSubviewToFront(head)
            bringSubviewToFront(caption)
        }

        private var laidOutSize: CGSize = .zero

        override func layoutSubviews() {
            super.layoutSubviews()
            followSize(of: self, laidOutAt: &laidOutSize)

            for text in texts { text.frame = bounds }

            titlePage?.frame = bounds
            missing?.frame = bounds
            painted.frame = bounds
            marks.frame = bounds
        }

        private func showText(_ pieces: [BookPage.Piece], on page: BookPage) {
            titlePage?.isHidden = true
            missing?.isHidden = true

            while texts.count < pieces.count {
                let text = ChapterPageView.PageView()

                text.backgroundColor = .clear
                text.isOpaque = false
                insertSubview(text, at: texts.count)
                texts.append(text)
            }

            // Two pieces where a chapter starts on the page the one before it ended on. Each draws only
            // its own lines, in its own place on the page.
            for (index, text) in texts.enumerated() {
                text.isHidden = index >= pieces.count

                guard index < pieces.count else { continue }

                text.frame = bounds
                text.apply(layout: pieces[index].layout, page: pieces[index].page)
            }

            paint(page)
            hangMarks(on: page)
        }

        /// What the reader drew a finger across, and the words searching took them to, painted under
        /// the words rather than over them: the page is drawn, so nothing on it has a colour of its own.
        private func paint(_ page: BookPage) {
            let picked = model.picked?.pageId == page.id ? model.picked?.rects ?? [] : []
            let rects = picked + model.foundRects(on: page)
            let colour = UIColor(Design.Surface.picked(stage.settings.theme.foreground)).cgColor

            painted.sublayers?.forEach { $0.removeFromSuperlayer() }

            for rect in rects {
                let box = CALayer()

                box.frame = rect
                box.cornerRadius = Design.Radius.small
                box.backgroundColor = colour
                painted.addSublayer(box)
            }

            // Under the text, which the page views draw above it.
            layer.insertSublayer(painted, at: 0)
        }

        /// A ribbon in the gutter against the line each mark begins on, contoured in the page's own ink.
        ///
        /// It shrinks with the margin it hangs in, and a page set with no margin keeps it at the edge.
        private func hangMarks(on page: BookPage) {
            let standing = model.marks(on: page)
            let textEdge = stage.layoutContext.textRect.maxX
            let pageWidth = bounds.width
            let room = max(0, pageWidth - textEdge)
            let scale = min(1, max(Self.leastMarkScale, (room - Design.Space.extraSmall) / Design.Size.bookmark))
            let size = CGSize(width: Design.Size.bookmark * scale, height: Design.Size.bookmarkHeight * scale)
            let ink = UIColor(stage.settings.theme.foreground.opacity(Self.markInk)).cgColor

            marks.sublayers?.forEach { $0.removeFromSuperlayer() }

            for mark in standing {
                let ribbon = CAShapeLayer()
                let x = min(max(textEdge + room / 2, size.width / 2), pageWidth - size.width / 2)

                ribbon.frame = CGRect(
                    x: x - size.width / 2,
                    y: mark.top + mark.height / 2 - size.height / 2,
                    width: size.width,
                    height: size.height
                )
                ribbon.path = BookmarkShape().path(in: CGRect(origin: .zero, size: size)).cgPath
                ribbon.fillColor = nil
                ribbon.strokeColor = ink
                ribbon.lineWidth = Design.Stroke.readingShade
                marks.addSublayer(ribbon)
            }

            layer.addSublayer(marks)
        }

        private func showTitle() {
            for text in texts { text.isHidden = true }

            missing?.isHidden = true
            painted.sublayers?.forEach { $0.removeFromSuperlayer() }
            marks.sublayers?.forEach { $0.removeFromSuperlayer() }

            let title = titlePage ?? TitlePageView(pictures: pictures)

            if titlePage == nil {
                titlePage = title
                insertSubview(title, at: 0)
            }

            let pageSafeArea = stage.spread.pageSafeArea

            title.isHidden = false
            title.frame = bounds
            title.apply(TitlePageView.Contents(
                title: model.bookTitle,
                author: model.book?.authorLine ?? "",
                seriesTitle: model.book?.seriesTitle,
                coverURL: model.book?.coverURL,
                style: stage.settings.textStyle,
                margins: stage.settings.settledMargins,
                safeArea: UIEdgeInsets(top: pageSafeArea.top, left: 0, bottom: pageSafeArea.bottom, right: 0)
            ))
        }

        private func showMissing() {
            for text in texts { text.isHidden = true }

            titlePage?.isHidden = true
            painted.sublayers?.forEach { $0.removeFromSuperlayer() }
            marks.sublayers?.forEach { $0.removeFromSuperlayer() }

            var configuration = UIContentUnavailableConfiguration.empty()
            let ink = UIColor(stage.settings.theme.foreground)

            configuration.image = UIImage(systemName: "book.closed")
            configuration.text = String(localized: "Couldn’t load this chapter.")
            configuration.textProperties.color = ink
            configuration.imageProperties.tintColor = ink

            let view = missing ?? UIContentUnavailableView(configuration: configuration)

            if missing == nil {
                missing = view
                insertSubview(view, at: 0)
            }

            view.configuration = configuration
            view.isHidden = false
            view.frame = bounds
        }

        /// A shade off the text's own ink: the mark is the reader's, not the book's.
        private static let markInk: CGFloat = 0.55

        /// How small the ribbon may be squeezed before it stops shrinking with the margin.
        private static let leastMarkScale: CGFloat = 0.5
    }

    /// How far into the book a page stands.
    ///
    /// Reading, that is the page's own number, standing where a printed book puts it. With the controls
    /// up it is the number against the book's length, with a bar beside it saying the same at a glance.
    @MainActor
    private final class Caption: UIView {
        private let figures = UILabel()
        private let bar = ProgressBarView()

        override init(frame: CGRect) {
            super.init(frame: frame)

            figures.isAccessibilityElement = false
            addSubview(figures)
            addSubview(bar)
            isAccessibilityElement = true
            accessibilityTraits = .staticText
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        private var wasChromeHidden: Bool?

        func apply(model: Model, stage: Stage, at position: BookPosition, isCurrent: Bool, in container: CGRect) {
            let changing = wasChromeHidden.map { $0 != stage.isChromeHidden } ?? false

            wasChromeHidden = stage.isChromeHidden

            let setting = { self.set(model: model, stage: stage, at: position, isCurrent: isCurrent, in: container) }

            // The figures take on the book's length and a bar as the controls come up, and give them back.
            if changing, window != nil {
                UIView.transition(
                    with: self,
                    duration: Stage.chromeFade,
                    options: .transitionCrossDissolve,
                    animations: setting
                )
            } else {
                setting()
            }
        }

        private func set(model: Model, stage: Stage, at position: BookPosition, isCurrent: Bool, in container: CGRect) {
            let size = stage.runningHeadSize * Stage.captionScale
            let share = model.progress(at: position)
            let page = model.pageNumber(at: position)
            let percent = share.formatted(.percent.precision(.fractionLength(0)))
            let foreground = stage.settings.theme.foreground
            let hidden = stage.isChromeHidden
            let context = stage.layoutContext
            let line = RunningHead.line(size)
            let bottom = stage.spread.pageSafeArea.bottom + RunningHead.air(context.runningHeadBand, size)

            frame = CGRect(
                x: container.width / 2 - context.textSize.width / 2,
                y: container.height - bottom - line,
                width: context.textSize.width,
                height: line
            )

            figures.font = .monospacedDigitSystemFont(ofSize: size, weight: .regular)
            figures.textColor = UIColor(foreground.opacity(hidden ? Stage.figureInk : Stage.figureInkShown))
            figures.text = hidden
                ? page?.formatted(.number) ?? percent
                : page.map { "\($0.formatted(.number))/\(model.bookPages?.formatted(.number) ?? "")" } ?? percent
            figures.sizeToFit()

            bar.isHidden = hidden
            bar.value = share
            bar.tint = UIColor(foreground.opacity(Stage.readInk))
            bar.track = UIColor(foreground.opacity(Stage.trackInk))

            if hidden {
                figures.frame = CGRect(x: 0, y: 0, width: bounds.width, height: line)
                figures.textAlignment = .center
            } else {
                let width = min(figures.bounds.width, bounds.width)
                let gap = size * Stage.progressSpacing
                let barHeight = Design.Space.extraSmall

                figures.textAlignment = .natural
                figures.frame = CGRect(x: 0, y: 0, width: width, height: line)
                bar.frame = CGRect(
                    x: width + gap,
                    y: (line - barHeight) / 2,
                    width: max(0, bounds.width - width - gap),
                    height: barHeight
                )
            }

            accessibilityLabel =
                page.flatMap { number in model.bookPages.map { String(localized: "page \(number) of \($0)") } }
                ?? String(localized: "\(percent) of the book")
            accessibilityIdentifier = isCurrent ? "reader.caption" : nil
            isAccessibilityElement = isCurrent
        }
    }
}

/// Sets out again at once when a view's size changed, since what it holds is placed from that size.
@MainActor
private func followSize(of view: UIView, laidOutAt size: inout CGSize) {
    guard view.bounds.size != size else { return }

    size = view.bounds.size
    view.setNeedsUpdateProperties()
    view.updatePropertiesIfNeeded()
}

extension ReaderScreen.Stage {
    /// Sets the book's title above the text: a little more ink while it is the only thing naming the
    /// page, and a step back while the controls carry that.
    func dressHead(_ head: UILabel, text: String, in width: CGFloat) {
        let ink = isChromeHidden ? Self.figureInk : Self.figureInkShown
        let colour = UIColor(settings.theme.foreground.opacity(ink))

        if head.window != nil, head.textColor != colour, head.text == text {
            UIView.transition(with: head, duration: Self.chromeFade, options: .transitionCrossDissolve) {
                head.textColor = colour
            }
        } else {
            head.textColor = colour
        }

        let size = runningHeadSize
        let context = layoutContext
        let margins = settings.settledMargins

        head.isHidden = text.isEmpty
        head.text = text
        head.font = .systemFont(ofSize: size)
        head.frame = CGRect(
            x: margins,
            y: spread.pageSafeArea.top + RunningHead.air(context.runningHeadBand, size),
            width: max(0, width - margins * 2),
            height: RunningHead.line(size)
        )
    }

    /// How far into the book the page is sits a little smaller than the book's title above it.
    static let captionScale: CGFloat = 0.9

    /// The air between the figures and the bar beside them, against the size they are set in.
    static let progressSpacing: CGFloat = 0.6

    /// The bar's ink, its read part and the rest.
    static let readInk: CGFloat = 0.3
    static let trackInk: CGFloat = 0.1

    /// The ink of what names the page: more while it is the only thing naming it.
    static let figureInk: CGFloat = 0.6
    static let figureInkShown: CGFloat = 0.4
}
