//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import DesignSystem
import UIKit

/// The line under a run of books that says where a series starts and where it ends.
///
/// The line ticks upward at the outer edge of the first book and of the last, and where a run carries on
/// onto the next row it is left open, so an unclosed end reads as "continues".
final class BracketView: UIView {
    var onMenu: (() -> UIMenu?)?

    private let name = UILabel()
    private var opens = false
    private var closes = false
    private var title = ""

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .clear
        isOpaque = false

        // Laid over the line rather than beside it. The line stops either side of the words rather than
        // behind them, so it reads the same on whatever it is drawn on.
        name.font = UIFont.systemFont(ofSize: Design.Style.spineSize, weight: .medium, width: .compressed)
        name.textColor = Self.ink
        name.textAlignment = .center
        addSubview(name)

        addInteraction(UIContextMenuInteraction(delegate: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(title: String, opens: Bool, closes: Bool) {
        self.title = title
        self.opens = opens
        self.closes = closes

        setNeedsLayout()
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Full name, then initials, then nothing. A name set in full on a line with no room for it
        // points at books that are not its own.
        for words in [ title, Self.initials(of: title), "" ] {
            name.text = words

            let width = words.isEmpty ? 0 : name.sizeThatFits(bounds.size).width + Design.Space.extraSmall * 2

            if width <= bounds.width || words.isEmpty {
                name.frame = CGRect(x: bounds.midX - width / 2, y: 0, width: width, height: bounds.height)
                break
            }
        }

        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        let line = bounds.midY
        let tick = line - Design.Space.small

        context.setStrokeColor(Self.rule.resolvedColor(with: traitCollection).cgColor)
        context.setLineWidth(Design.Stroke.hairline)
        context.move(to: CGPoint(x: bounds.minX, y: line))
        context.addLine(to: CGPoint(x: max(bounds.minX, name.frame.minX), y: line))
        context.move(to: CGPoint(x: min(bounds.maxX, name.frame.maxX), y: line))
        context.addLine(to: CGPoint(x: bounds.maxX, y: line))

        if opens {
            context.move(to: CGPoint(x: bounds.minX, y: line))
            context.addLine(to: CGPoint(x: bounds.minX, y: tick))
        }

        if closes {
            context.move(to: CGPoint(x: bounds.maxX, y: line))
            context.addLine(to: CGPoint(x: bounds.maxX, y: tick))
        }

        context.strokePath()
    }

    /// The name and the line, dark enough to read on the plank they are drawn on.
    private static let ink = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .secondaryLabel.resolvedColor(with: traits)
            : .black.withAlphaComponent(Bookcase.lightPlankInk)
    }

    private static let rule = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .tertiaryLabel.resolvedColor(with: traits)
            : .black.withAlphaComponent(Bookcase.lightPlankRule)
    }

    /// A name the line has no room for, as the letters its words begin with.
    static func initials(of title: String) -> String {
        title
            .split { !$0.isLetter && !$0.isNumber }
            .compactMap(\.first)
            .map { "\($0)." }
            .joined()
    }
}

extension BracketView: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let menu = onMenu?() else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menu }
    }
}
