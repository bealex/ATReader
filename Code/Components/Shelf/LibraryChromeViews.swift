//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import DesignSystem
import UIKit

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
