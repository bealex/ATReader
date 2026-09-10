//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import DesignSystem
import UIKit

/// The shelf's own heading: what it is, what it is showing, and what can be done to the whole of it.
///
/// The shelf carries no navigation bar, so this is where its name and its controls live.
final class LibraryHeaderView: UIView {
    /// What the heading says and what its buttons do.
    struct Contents {
        let title: String
        /// Which books are being shown, named under the title.
        let showing: String
        let isSelecting: Bool
        let isImporting: Bool
        /// The two menus, as lists the shelf and its rows both set out from.
        let merge: [Deed]
        let filters: [Deed]
        let onSelect: @MainActor () -> Void
        let onAdd: @MainActor () -> Void
    }

    private let name = UILabel()
    private let showing = UILabel()
    private let merge = UIButton(type: .system)
    private let select = UIButton(type: .system)
    private let add = UIButton(type: .system)
    private let filter = UIButton(type: .system)

    private var contents: Contents?

    override init(frame: CGRect) {
        super.init(frame: frame)

        name.font = UIFont.preferredFont(forTextStyle: .largeTitle).bold
        name.adjustsFontForContentSizeCategory = true
        showing.font = UIFont.preferredFont(forTextStyle: .subheadline)
        showing.textColor = .secondaryLabel
        showing.adjustsFontForContentSizeCategory = true

        for view in [ name, showing, merge, select, add, filter ] { addSubview(view) }

        for button in [ merge, select, add, filter ] {
            button.setPreferredSymbolConfiguration(
                UIImage.SymbolConfiguration(pointSize: Design.Control.barGlyphSize),
                forImageIn: .normal
            )
        }

        select.addAction(UIAction { [weak self] _ in self?.contents?.onSelect() }, for: .primaryActionTriggered)
        add.addAction(UIAction { [weak self] _ in self?.contents?.onAdd() }, for: .primaryActionTriggered)
        merge.showsMenuAsPrimaryAction = true
        filter.showsMenuAsPrimaryAction = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ contents: Contents) {
        self.contents = contents

        name.text = contents.title
        showing.text = contents.showing
        merge.menu = contents.merge.offered
        merge.setImage(UIImage(systemName: "arrow.triangle.merge"), for: .normal)
        merge.accessibilityIdentifier = "library.merge"
        merge.accessibilityLabel = String(localized: "Combine")
        merge.accessibilityHint = String(localized: "Holds two series, or two spellings of a name, together")

        select.setImage(UIImage(systemName: contents.isSelecting ? "xmark" : "checklist"), for: .normal)
        select.accessibilityIdentifier = "library.select"
        select.accessibilityLabel = contents.isSelecting
            ? String(localized: "Stop picking books")
            : String(localized: "Pick books out")
        select.accessibilityHint = String(localized: "Combines the books you pick into one series")

        add.setImage(UIImage(systemName: contents.isImporting ? "hourglass" : "plus"), for: .normal)
        add.isEnabled = !contents.isImporting
        add.accessibilityIdentifier = "library.add"
        add.accessibilityLabel = String(localized: "Add a book from a file")
        add.accessibilityHint = String(localized: "Reads an FB2 file into your library")

        filter.menu = contents.filters.offered
        filter.setImage(UIImage(systemName: "line.3.horizontal.decrease.circle"), for: .normal)
        filter.accessibilityLabel = String(localized: "Choose what to show")
        filter.accessibilityHint = String(localized: "Filters your library")

        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        var right = bounds.maxX

        // Laid out from the trailing edge back, so the buttons keep their order however wide they are.
        for button in [ filter, add, select, merge ] {
            let width = max(Design.Size.touch, button.intrinsicContentSize.width)

            button.frame = CGRect(x: right - width, y: 0, width: width, height: Design.Size.touch)
            right -= width
        }

        let across = right - bounds.minX - Shelf.gutter

        name.frame = CGRect(x: 0, y: 0, width: across, height: name.font.lineHeight)
        showing.frame = CGRect(
            x: 0,
            y: name.frame.maxY + Design.Space.extraSmall,
            width: across,
            height: showing.font.lineHeight
        )
    }

    /// How deep the heading comes out, which the list has to know before there is one.
    static var height: CGFloat {
        let title = UIFont.preferredFont(forTextStyle: .largeTitle).bold.lineHeight
        let showing = UIFont.preferredFont(forTextStyle: .subheadline).lineHeight

        return max(title + Design.Space.extraSmall + showing, Design.Size.touch)
    }
}

/// The shelf's own search field, since the shelf has no navigation bar to put one in.
///
/// Filtering the library by title isn't the same question as searching the catalogue, which is the
/// search tab's job.
final class LibrarySearchView: UIView {
    private let glass = UIImageView(image: UIImage(systemName: "magnifyingglass"))
    private let field = UITextField()
    private let clear = UIButton(type: .system)

    private var onSearch: (@MainActor (String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = UIColor(Design.Surface.card)
        layer.cornerRadius = Design.Radius.medium
        layer.cornerCurve = .continuous

        glass.tintColor = .secondaryLabel
        glass.contentMode = .center
        field.placeholder = String(localized: "Title or author")
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.clearButtonMode = .never
        field.accessibilityLabel = String(localized: "Search your library")
        field.addAction(UIAction { [weak self] _ in self?.typed() }, for: .editingChanged)

        clear.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        clear.tintColor = .secondaryLabel
        clear.accessibilityLabel = String(localized: "Clear the search")
        clear.addAction(UIAction { [weak self] _ in self?.cleared() }, for: .primaryActionTriggered)

        for view in [ glass, field, clear ] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The text is only put back when it differs, since setting it under a finger that is typing moves
    /// the caret to the end of the line.
    func show(_ text: String, onSearch: @escaping @MainActor (String) -> Void) {
        self.onSearch = onSearch

        if field.text != text { field.text = text }

        clear.isHidden = text.isEmpty
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let glyph = Design.Size.mark

        glass.frame = CGRect(x: Design.Space.large, y: 0, width: glyph, height: bounds.height)
        clear.frame = CGRect(x: bounds.maxX - Design.Space.large - glyph, y: 0, width: glyph, height: bounds.height)

        let start = glass.frame.maxX + Design.Space.medium
        let end = clear.isHidden ? bounds.maxX - Design.Space.large : clear.frame.minX - Design.Space.medium

        field.frame = CGRect(x: start, y: 0, width: max(0, end - start), height: bounds.height)
    }

    private func typed() { onSearch?(field.text ?? "") }

    private func cleared() {
        field.text = ""
        typed()
    }

    static var height: CGFloat {
        UIFont.preferredFont(forTextStyle: .body).lineHeight + Design.Space.medium * 2
    }
}

extension UIFont {
    /// The same face, set bold, for a role the system names without one.
    var bold: UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }

        return UIFont(descriptor: descriptor, size: 0)
    }
}
