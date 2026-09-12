//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import DesignSystem
import UIKit

/// An author's name over their bookcase, with the chevron that turns it round. The list pins it to the
/// top while that author's books scroll under it.
final class AuthorHeaderView: UICollectionReusableView {
    var onToggle: (() -> Void)?
    var menu: (() -> UIMenu?)?

    /// True while the header is pinned over books scrolling under it, when the blur the list draws under
    /// the navigation bar is carried down under the header too, so the two read as one bar.
    var isFloating = false {
        didSet {
            guard isFloating != oldValue else { return }

            edgeEffect.scrollView = isFloating ? superview as? UIScrollView : nil
        }
    }

    private let edgeEffect = UIScrollEdgeElementContainerInteraction()
    private let name = UILabel()
    /// The whole header is the control, so the chevron is only its picture, turned about its own middle.
    private let chevron = UIImageView(
        image: UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(textStyle: .headline))
    )
    private var isOpen = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        edgeEffect.edge = .top
        addInteraction(edgeEffect)

        name.font = Self.nameFont
        name.numberOfLines = 1
        name.lineBreakMode = .byTruncatingTail
        name.adjustsFontForContentSizeCategory = true

        chevron.tintColor = .secondaryLabel
        chevron.contentMode = .center

        addSubview(name)
        addSubview(chevron)

        isAccessibilityElement = true
        accessibilityTraits = [ .header, .button ]
        accessibilityHint = String(localized: "Switches between every cover and the books left to read")
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        addInteraction(UIContextMenuInteraction(delegate: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Shows an author's name, and which way round their bookcase stands: open while every cover is out.
    func show(name: String, isOpen: Bool, animated: Bool) {
        self.name.text = name
        accessibilityLabel = name

        guard isOpen != self.isOpen || !animated else { return }

        self.isOpen = isOpen

        let turned = isOpen ? CGAffineTransform(rotationAngle: .pi) : .identity

        if animated {
            UIView.animate(withDuration: FoldMotion.turningSeconds) { self.chevron.transform = turned }
        } else {
            chevron.transform = turned
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Level with the bookcase's own edges, which stand in from the list's.
        let edge = Design.Space.extraLarge
        let line = Self.lineHeight
        let glyph = chevron.intrinsicContentSize

        // Bounds and centre rather than a frame, which means nothing once the chevron is turned.
        chevron.bounds = CGRect(origin: .zero, size: glyph)
        chevron.center = CGPoint(x: bounds.width - edge - glyph.width / 2, y: Self.above + line / 2)
        name.frame = CGRect(
            x: edge,
            y: Self.above,
            width: max(0, bounds.width - edge * 2 - glyph.width - Design.Space.medium),
            height: line
        )
    }

    override func accessibilityActivate() -> Bool {
        onToggle?()
        return true
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        isFloating = false
    }

    /// How tall the header stands at the reader's type size: the room above the name, its one line, and
    /// the room between it and the bookcase.
    static var height: CGFloat { above + lineHeight + between }

    private static let above = Design.Space.medium
    private static let between = Design.Space.small

    /// How much larger than a headline the name stands: it heads a bookcase rather than a row.
    private static let nameScale: CGFloat = 1.3

    /// A headline's weight, larger, and still following Dynamic Type.
    private static var nameFont: UIFont {
        let standard = UIFont.preferredFont(
            forTextStyle: .headline,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        )

        return UIFontMetrics(forTextStyle: .headline)
            .scaledFont(for: .systemFont(ofSize: standard.pointSize * nameScale, weight: .semibold))
    }

    /// Kept by type size, since the layout asks for every header's height on every frame of a turn.
    private static var lineHeight: CGFloat {
        let size = UIApplication.shared.preferredContentSizeCategory

        if let held = lineHeights[size] { return held }

        let line = nameFont.lineHeight.rounded(.up)

        lineHeights[size] = line
        return line
    }

    private static var lineHeights: [UIContentSizeCategory: CGFloat] = [:]

    @objc
    private func tapped() { onToggle?() }
}

extension AuthorHeaderView: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let menu = menu?() else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menu }
    }
}
