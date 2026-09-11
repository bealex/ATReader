//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import DesignSystem
import UIKit

/// Everything of one author's, in one bookcase: their name above it, their series in runs on its
/// shelves, and after them whatever stands on its own.
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

        return Self.above + Self.headerHeight(contents, across: width) + Self.between + turning
    }

    var nameMenu: (() -> UIMenu?)?

    private let header = UIView()
    private let name = UILabel()
    private var contents: Contents?

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .clear
        clipsToBounds = true

        name.font = Self.nameFont
        name.numberOfLines = 2
        name.adjustsFontForContentSizeCategory = true

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
        shelf.show(contents.shelf)
        setNeedsLayout()
    }

    /// Turns the whole card's shelf round, books and rows together.
    func turn(to contents: Contents, animated: Bool) {
        self.contents = contents

        name.text = contents.name
        shelf.turn(to: contents.shelf, animated: animated)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Level with the bookcase's own edge rather than with the books inside it.
        let across = bounds.width
        let deep = Self.headerHeight(contents, across: across)

        header.frame = CGRect(x: 0, y: Self.above, width: across, height: deep)
        name.frame = CGRect(x: 0, y: 0, width: across - Shelf.gutter, height: deep)
        shelf.frame = CGRect(
            x: 0,
            y: header.frame.maxY + Self.between,
            width: bounds.width,
            height: bounds.height - header.frame.maxY - Self.between
        )
    }

    /// How tall this card comes out, which the list has to know before the card exists.
    static func height(_ contents: Contents, across width: CGFloat) -> CGFloat {
        above
            + headerHeight(contents, across: width)
            + between
            + ShelfView.height(contents.shelf, across: width)
    }

    /// The room over the author's name, and between it and the top of the bookcase.
    private static let above = Design.Space.small
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

    private static func headerHeight(_ contents: Contents?, across width: CGFloat) -> CGFloat {
        guard let contents else { return 0 }

        let key = "\(contents.name)|\(width)|\(UIApplication.shared.preferredContentSizeCategory.rawValue)"

        if let held = measuredNames[key] { return held }

        let font = nameFont
        let box = (contents.name as NSString).boundingRect(
            with: CGSize(width: width - Shelf.gutter, height: .greatestFiniteMagnitude),
            options: [ .usesLineFragmentOrigin, .usesFontLeading ],
            attributes: [ .font: font ],
            context: nil
        )
        let height = min(box.height, font.lineHeight * 2).rounded(.up)

        measuredNames[key] = height
        return height
    }

    /// Names measured before, by name, width and type size: every card is measured again whenever the
    /// cards change, and a name set in text is the slowest part of it.
    private static var measuredNames: [String: CGFloat] = [:]

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
