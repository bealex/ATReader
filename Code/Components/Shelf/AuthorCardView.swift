//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import DesignSystem
import UIKit

/// Everything of one author's, on one card: their name, their series in runs, and after them whatever
/// stands on its own.
///
/// A reader follows writers more than they follow series, so one card holds an author's whole shelf. It
/// lays itself out rather than being laid out, because the list has to know how tall the card comes out
/// before there is a card to ask.
final class AuthorCardView: UIView {
    struct Contents {
        /// The author this card is of, which is what the list follows a card by.
        let id: String
        let name: String
        let shelf: ShelfView.Contents
        /// Whether every book of theirs is picked out, while the shelf is picking books.
        let isPicked: Bool?
    }

    let shelf = ShelfView()

    var onName: (() -> Void)?
    /// Called on every frame of a turn, for whatever has to follow the card as it changes height.
    var onFrame: (() -> Void)? {
        get { shelf.onFrame }
        set { shelf.onFrame = newValue }
    }

    /// How far through its turn this card is, which is what its height is worth on the way.
    var reached: CGFloat { shelf.reached }

    /// How tall this card stands at this moment, across the width it is being given.
    ///
    /// A card knows its own height: a list that works one out for it has to be told again on every frame
    /// of a turn, and a collection view will not carry a card from one worked-out height to another
    /// however the change is made. The width is handed in rather than read off the card, which has none
    /// worth reading until it has been laid out and is asked this before it ever is.
    func height(across width: CGFloat) -> CGFloat {
        guard let contents else { return 0 }
        guard let turning = shelf.turningHeight else { return Self.height(contents, across: width) }

        return Design.Space.medium
            + Self.headerHeight(contents, across: width - Design.Space.large * 2)
            + Design.Space.medium
            + turning
            + Design.Space.large
    }

    var nameMenu: (() -> UIMenu?)?

    private let header = UIView()
    private let name = UILabel()
    private let tick = UIImageView()
    private var contents: Contents?

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = UIColor(Design.Surface.card)
        layer.cornerRadius = Design.Radius.large
        layer.cornerCurve = .continuous
        clipsToBounds = true

        name.font = UIFont.preferredFont(forTextStyle: .headline)
        name.numberOfLines = 2
        name.adjustsFontForContentSizeCategory = true

        header.addSubview(tick)
        header.addSubview(name)
        header.isAccessibilityElement = true
        header.accessibilityTraits = .button
        header.accessibilityHint = String(localized: "Switches between every cover and the books left to read")
        header.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        header.addInteraction(UIContextMenuInteraction(delegate: self))
        addSubview(header)
        addSubview(shelf)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ contents: Contents) {
        self.contents = contents

        name.text = contents.name
        header.accessibilityLabel = contents.name
        paint()
        shelf.show(contents.shelf)
        setNeedsLayout()
    }

    /// Turns the whole card's shelf round, books and rows together.
    func turn(to contents: Contents, animated: Bool) {
        self.contents = contents

        name.text = contents.name
        paint()
        shelf.turn(to: contents.shelf, animated: animated)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let inset = Design.Space.large
        let across = bounds.width - inset * 2
        let deep = Self.headerHeight(contents, across: across)

        header.frame = CGRect(x: inset, y: Design.Space.medium, width: across, height: deep)

        let glyph = tick.isHidden ? 0 : Design.Control.barGlyphSize + Design.Space.medium

        tick.frame = CGRect(x: 0, y: 0, width: Design.Control.barGlyphSize, height: deep)
        name.frame = CGRect(x: glyph, y: 0, width: across - glyph - Shelf.gutter, height: deep)
        shelf.frame = CGRect(
            x: inset,
            y: header.frame.maxY + Design.Space.medium,
            width: across,
            height: bounds.height - header.frame.maxY - Design.Space.medium - Design.Space.large
        )
    }

    /// How tall this card comes out, which the list has to know before the card exists.
    static func height(_ contents: Contents, across width: CGFloat) -> CGFloat {
        let across = width - Design.Space.large * 2

        return Design.Space.medium
            + headerHeight(contents, across: across)
            + Design.Space.medium
            + ShelfView.height(contents.shelf, across: across)
            + Design.Space.large
    }

    private static func headerHeight(_ contents: Contents?, across width: CGFloat) -> CGFloat {
        guard let contents else { return 0 }

        let font = UIFont.preferredFont(forTextStyle: .headline)
        let glyph = contents.isPicked == nil ? 0 : Design.Control.barGlyphSize + Design.Space.medium
        let box = (contents.name as NSString).boundingRect(
            with: CGSize(width: width - glyph - Shelf.gutter, height: .greatestFiniteMagnitude),
            options: [ .usesLineFragmentOrigin, .usesFontLeading ],
            attributes: [ .font: font ],
            context: nil
        )

        return min(box.height, font.lineHeight * 2).rounded(.up)
    }

    private func paint() {
        guard let picked = contents?.isPicked else { return tick.isHidden = true }

        tick.isHidden = false
        tick.image = UIImage(
            systemName: picked ? "checkmark.circle.fill" : "circle",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: Design.Control.barGlyphSize)
        )
        tick.tintColor = picked ? .tintColor : .tertiaryLabel
        tick.contentMode = .center
    }

    @objc
    private func tapped() { onName?() }
}

extension AuthorCardView: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let menu = nameMenu?() else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menu }
    }
}
