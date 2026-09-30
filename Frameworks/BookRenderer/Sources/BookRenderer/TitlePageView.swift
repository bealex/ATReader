//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import UIKit

/// The page a book opens on: cover, title, author and series, set in the reader's own typeface.
@MainActor
public final class TitlePageView: UIView {
    public struct Contents: Equatable {
        public var title: String
        public var author: String
        public var seriesTitle: String?
        public var coverURL: URL?
        public var style: ChapterTextStyle
        public var margins: Double
        public var safeArea: UIEdgeInsets

        public init(
            title: String,
            author: String,
            seriesTitle: String?,
            coverURL: URL?,
            style: ChapterTextStyle,
            margins: Double,
            safeArea: UIEdgeInsets
        ) {
            self.title = title
            self.author = author
            self.seriesTitle = seriesTitle
            self.coverURL = coverURL
            self.style = style
            self.margins = margins
            self.safeArea = safeArea
        }
    }

    private let cover = PagePictureView()
    private let title = UILabel()
    private let author = UILabel()
    private let series = UILabel()
    private var contents: Contents?

    public init(pictures: (any PagePictureLoading)?) {
        super.init(frame: .zero)

        cover.pictures = pictures

        for label in [ title, author, series ] {
            label.numberOfLines = 0
            label.textAlignment = .center
            addSubview(label)
        }

        addSubview(cover)
        isAccessibilityElement = true
        accessibilityTraits = .staticText
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func apply(_ contents: Contents) {
        guard contents != self.contents else { return }

        self.contents = contents

        let style = contents.style
        let ink = style.textColor
        let weight = style.weight.uiWeight

        backgroundColor = style.backgroundColor
        title.font = style.face.font(size: style.fontSize * Self.titleScale, weight: weight)
        title.textColor = ink
        title.text = contents.title
        author.font = style.face.font(size: style.fontSize, weight: weight)
        author.textColor = ink.withAlphaComponent(Self.authorInk)
        author.text = contents.author
        series.font = style.face.font(size: style.fontSize * Self.seriesScale, weight: weight)
        series.textColor = ink.withAlphaComponent(Self.seriesInk)
        series.text = contents.seriesTitle
        series.isHidden = contents.seriesTitle?.isEmpty ?? true
        cover.show(contents.coverURL, palette: style.palette)
        // Joined rather than interpolated into a key: these are the book's own words.
        accessibilityLabel = [ contents.title, contents.author, contents.seriesTitle ].compactMap(\.self)
            .joined(separator: ", ")
        setNeedsLayout()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        guard let contents else { return }

        let side = max(contents.margins, Self.leastMargin)
        let width = max(0, bounds.width - side * 2)
        let fit = CGSize(width: width, height: .greatestFiniteMagnitude)
        let coverSize = cover.size(forWidth: Self.coverWidth)
        let titleHeight = title.sizeThatFits(fit).height
        let authorHeight = author.sizeThatFits(fit).height
        let seriesHeight = series.isHidden ? 0 : series.sizeThatFits(fit).height
        let total =
            coverSize.height + Self.coverGap + titleHeight + Self.titleGap + authorHeight
            + (series.isHidden ? 0 : Self.seriesGap + seriesHeight)
        let room = bounds.height - contents.safeArea.top - contents.safeArea.bottom
        var y = contents.safeArea.top + (room - total) / 2

        cover.frame = CGRect(origin: CGPoint(x: (bounds.width - coverSize.width) / 2, y: y), size: coverSize)
        y += coverSize.height + Self.coverGap
        title.frame = CGRect(x: side, y: y, width: width, height: titleHeight)
        y += titleHeight + Self.titleGap
        author.frame = CGRect(x: side, y: y, width: width, height: authorHeight)
        y += authorHeight + Self.seriesGap
        series.frame = CGRect(x: side, y: y, width: width, height: seriesHeight)
    }

    private static let coverWidth: CGFloat = 255
    private static let coverGap: CGFloat = 32
    private static let titleGap: CGFloat = 14
    private static let seriesGap: CGFloat = 18
    private static let titleScale: CGFloat = 1.7
    private static let seriesScale: CGFloat = 0.85
    private static let authorInk: CGFloat = 0.7
    private static let seriesInk: CGFloat = 0.5
    private static let leastMargin: Double = 24
}

/// A cover drawn the way the reader draws every other picture in a book, in the page's own colours.
@MainActor
final class PagePictureView: UIView {
    var pictures: (any PagePictureLoading)?

    private var url: URL?
    private var palette: PagePalette?
    private var picture: PageImage?
    private var loading: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)

        isOpaque = false
        backgroundColor = .clear
        layer.masksToBounds = true
        layer.borderWidth = Self.border
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ url: URL?, palette: PagePalette) {
        self.palette = palette
        layer.borderColor = palette.foreground.withAlphaComponent(Self.borderInk).cgColor
        setNeedsDisplay()

        guard url != self.url else { return }

        self.url = url
        picture = nil
        loading?.cancel()

        guard let url, let pictures else { return }

        loading = Task { [weak self] in
            let loaded = await pictures.picture(at: url)

            guard !Task.isCancelled, let self, self.url == url else { return }

            picture = loaded
            superview?.setNeedsLayout()
            setNeedsDisplay()
        }
    }

    /// How big the cover stands at `width`: its own proportions, or a book's where there is none yet.
    func size(forWidth width: CGFloat) -> CGSize {
        guard let picture, picture.size.width > 0 else { return CGSize(width: width, height: width * Self.bookShape) }

        return CGSize(width: width, height: width * picture.size.height / picture.size.width)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width * Self.rounding
    }

    override func draw(_ rect: CGRect) {
        guard let picture, let palette, let context = UIGraphicsGetCurrentContext() else { return }

        picture.draw(in: bounds, palette: palette, into: context)
    }

    private static let bookShape: CGFloat = 1.5
    private static let rounding: CGFloat = 0.08
    private static let border: CGFloat = 0.5
    private static let borderInk: CGFloat = 0.15
}
