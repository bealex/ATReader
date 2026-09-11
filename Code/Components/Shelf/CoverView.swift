//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import DesignSystem
import SwiftUI
import UIKit

/// A book's face: its artwork, the board bending into its binding, and the few marks a shelf puts on it.
final class CoverView: UIView {
    /// What a cover shows besides the picture.
    struct Marks {
        var progress: Double?
        var isComplete = false
        var origin: CoverOrigin?
        var isOngoing = false
        /// Which way the book's own colour runs, which is what its marks are set against.
        var isDark = false

        func with(isDark: Bool) -> Marks {
            var marks = self

            marks.isDark = isDark

            return marks
        }
    }

    /// The printed face, or the bare board standing in for it until the face arrives.
    private let face = UIImageView()
    /// What a book with no cover at all shows, and the marks over a face, each made the first time a
    /// book needs it: a card coming into view makes every book on it, and most need none of these.
    private var placeholder: UIImageView?
    private var progress: UIImageView?
    private var source: UIImageView?
    private var ongoing: UIImageView?

    private var marks = Marks()
    private var url: URL?
    /// The face hanging now, where it is a printed one rather than the bare board.
    private var shown: CoverPrint.Order?
    private var loading: (order: CoverPrint.Order, task: Task<Void, Never>)?

    /// Whether the face can be seen. A book standing on its edge has no use for its cover's picture, so
    /// nothing is decoded or drawn for it until it turns.
    var wantsArtwork = false {
        didSet {
            guard wantsArtwork != oldValue else { return }

            refreshFace()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        face.contentMode = .scaleToFill
        addSubview(face)

        registerForTraitChanges([ UITraitUserInterfaceStyle.self ]) { (self: Self, _) in
            self.paint()
            self.refreshFace()
        }
        paint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// What this cover is of, from the book's own artwork down to the marks over it.
    func show(_ work: Book, marks: Marks) {
        self.marks = marks

        if url != work.coverURL {
            url = work.coverURL
            stopLoading()
        }

        if url == nil {
            let placeholder = made(&placeholder)

            placeholder.contentMode = .center
            placeholder.image = UIImage(systemName: "book.closed")
            placeholder.isHidden = false
        } else {
            placeholder?.isHidden = true
        }

        paint()
        refreshFace()
    }

    /// One of the views a book makes only when it needs it, made now if it hasn't been.
    private func made(_ view: inout UIImageView?) -> UIImageView {
        if let view { return view }

        let new = UIImageView()

        addSubview(new)
        view = new
        setNeedsLayout()

        return new
    }

    /// Told when the picture finally arrives, since a spine printed without it has to be printed again.
    var onArtwork: (() -> Void)?

    /// Gives up the face on its way, for a book that has left the screen.
    func stopLoading() {
        loading?.task.cancel()
        loading = nil
    }

    /// Asks again for a face given up while the book was off the screen.
    func resumeLoading() { refreshFace() }

    override func layoutSubviews() {
        super.layoutSubviews()

        face.frame = bounds
        placeholder?.frame = bounds
        placeholder?.preferredSymbolConfiguration = .init(pointSize: bounds.width * 0.3)

        let inset = Design.Space.extraSmall
        let mark = Design.Size.mark

        progress?.frame = CGRect(
            x: bounds.maxX - inset - mark,
            y: bounds.maxY - inset - mark,
            width: mark,
            height: mark
        )
        source?.frame = CGRect(x: inset, y: inset, width: mark, height: mark)
        ongoing?.frame = CGRect(x: inset, y: bounds.maxY - inset - mark, width: mark, height: mark)

        refreshFace()
    }

    /// Hangs the printed face where it is at hand, and otherwise the bare board, printing the face in
    /// the background and fading it in once it is.
    private func refreshFace() {
        let isDark = traitCollection.userInterfaceStyle == .dark

        guard
            let url,
            bounds.width > 0,
            bounds.height > 0
        else {
            stopLoading()
            shown = nil
            face.image = CoverPrint.blank(isDark: isDark)
            return
        }

        let order = CoverPrint.Order(url: url, size: bounds.size, isDark: isDark)

        guard shown != order else { return }

        if let held = CoverPrint.held(order) {
            stopLoading()
            face.image = held
            shown = order
            return
        }

        // Another book's face never stands in for this one; this book's own at another size can.
        if shown?.url != url || shown?.isDark != isDark {
            face.image = CoverPrint.blank(isDark: isDark)
            shown = nil
        }

        guard wantsArtwork else { return stopLoading() }
        guard loading?.order != order else { return }

        stopLoading()
        loading = (
            order,
            Task { [weak self] in
                guard let printed = await CoverPrint.printed(order) else { return }
                guard let self, !Task.isCancelled, self.loading?.order == order else { return }

                self.loading = nil
                self.shown = order
                self.face.arrive(printed)
                self.onArtwork?()
            }
        )
    }

    /// The marks over the face, which take the room's colours rather than the book's.
    private func paint() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        let scheme =
            isDark ? UITraitCollection(userInterfaceStyle: .dark) : UITraitCollection(userInterfaceStyle: .light)
        let neutral = UIColor(Design.Palette.neutral).resolvedColor(with: scheme)

        placeholder?.tintColor = UIColor.tertiaryLabel

        if let read = marks.progress, read > 0 {
            let progress = made(&progress)

            progress.image = MarkPrint.progress(read, isComplete: marks.isComplete, isDark: isDark)
            progress.isHidden = false
        } else {
            progress?.isHidden = true
        }

        if let origin = marks.origin {
            let source = made(&source)

            source.image = MarkPrint.circle(origin.systemImage, tint: neutral, isDark: isDark)
            source.isHidden = false
        } else {
            source?.isHidden = true
        }

        if marks.isOngoing {
            let ongoing = made(&ongoing)

            ongoing.image = MarkPrint.circle("pencil", tint: neutral, isDark: isDark)
            ongoing.isHidden = false
        } else {
            ongoing?.isHidden = true
        }
    }
}
