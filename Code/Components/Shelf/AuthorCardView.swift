//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import UIKit

/// Everything of one author's, in one bookcase: their series in runs on its shelves, and after them
/// whatever stands on its own. Their name stands over it in an `AuthorHeaderView`.
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

    /// How far the books on this card have gone, for a bookcase shutting over them.
    var emptied: CGFloat = 0 {
        didSet {
            guard oldValue != emptied else { return }

            shelf.shown = 1 - emptied
        }
    }

    /// How far off the trailing side this card has gone, fading as it goes. Its own edge clips it, so a
    /// card leaving never draws over the ones closing up around it.
    var aside: CGFloat = 0 {
        didSet {
            guard oldValue != aside else { return }

            setNeedsLayout()
        }
    }

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

        return shelf.turningHeight ?? Self.height(contents, across: width)
    }

    private var contents: Contents?

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .clear
        clipsToBounds = true
        addSubview(shelf)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ contents: Contents) {
        self.contents = contents

        shelf.show(contents.shelf)
        // A card that came back while it was leaving stands as it stood, rather than where its
        // departure had carried it to.
        emptied = 0
        aside = 0
        setNeedsLayout()
    }

    /// Turns the whole card's shelf round, books and rows together.
    func turn(to contents: Contents, animated: Bool) {
        self.contents = contents

        shelf.turn(to: contents.shelf, animated: animated)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let trailing: CGFloat = effectiveUserInterfaceLayoutDirection == .rightToLeft ? -1 : 1

        shelf.frame = bounds.offsetBy(dx: trailing * aside * bounds.width, dy: 0)
        shelf.alpha = 1 - aside
    }

    /// How tall this card comes out, which the list has to know before the card exists.
    static func height(_ contents: Contents, across width: CGFloat) -> CGFloat {
        ShelfView.height(contents.shelf, across: width)
    }
}
