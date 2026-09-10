//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import BookStorage
import UIKit

/// Prints a whole library's spines, and pulls in its covers, before the reader scrolls to them.
///
/// A spine is a blurred, resaturated copy of its own cover, which costs a CoreImage pass to make. Made
/// while the shelf is moving, that pass lands in the middle of a frame.
@MainActor
enum SpinePress {
    /// One spine a shelf is going to want: which book, how it is labelled, and how big it stands.
    struct Wanted: Hashable {
        let id: Int
        let coverURL: URL?
        let number: Int?
        let title: String
        let size: CGSize
    }

    /// Prints every one of these, in the order they stand. Asked for the same set again it does
    /// nothing; asked for a different one it drops whatever it was printing and starts on that.
    static func press(_ wanted: [Wanted], isDark: Bool) {
        var hasher = Hasher()

        hasher.combine(wanted)
        hasher.combine(isDark)

        let asked = hasher.finalize()

        guard asked != pressed else { return }

        pressed = asked
        running?.cancel()
        running = Task(priority: .utility) { await run(wanted, isDark: isDark, density: SpinePrint.density) }
    }

    /// Pulls covers off the disk for a card about to come into view, for the ones a whole library's
    /// worth of them has already pushed out of memory.
    ///
    /// One set at a time, the latest asked for: a fling asks for a hundred cards it goes straight
    /// past, and the reader is only ever waiting on the last of them.
    static func warm(_ urls: [URL]) {
        warming?.cancel()
        warming = Task(priority: .utility) {
            for url in urls where !Task.isCancelled { _ = await cover(at: url) }
        }
    }

    /// Prints one spine the run hasn't reached, for a shelf that needs it now. Filed like any other,
    /// so the book beside it on the next card finds it already printed.
    static func printed(of work: Book, number: Int?, title: String, size: CGSize, isDark: Bool) async -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }

        let artwork = await cover(at: work.coverURL)
        let order = SpinePrint.Order(
            id: work.id,
            number: number,
            title: title,
            size: size,
            isDark: isDark,
            hasArtwork: artwork != nil
        )

        if let held = SpinePrint.held(order) { return held }

        return SpinePrint.keep(
            await Press.shared.pull(order, artwork: artwork, density: SpinePrint.density),
            for: order
        )
    }

    private static var running: Task<Void, Never>?
    private static var warming: Task<Void, Never>?

    /// What the last run was asked for, so a shelf redrawn for a cover landing doesn't start over.
    private static var pressed: Int?

    private static func run(_ wanted: [Wanted], isDark: Bool, density: CGFloat) async {
        for one in wanted {
            guard !Task.isCancelled else { return }

            let artwork = await cover(at: one.coverURL)
            let order = SpinePrint.Order(
                id: one.id,
                number: one.number,
                title: one.title,
                size: one.size,
                isDark: isDark,
                hasArtwork: artwork != nil
            )

            guard !SpinePrint.has(order) else { continue }

            SpinePrint.keep(await Press.shared.pull(order, artwork: artwork, density: density), for: order)
        }
    }

    /// The cover this device already has, from memory or from its own disk, and never off the network:
    /// a book whose artwork has yet to arrive is printed bare and printed again when it lands.
    private static func cover(at url: URL?) async -> UIImage? {
        guard let url else { return nil }

        if let held = CoverImages.image(for: url) { return held }
        guard let held = await CoverCache.shared.held(for: url) else { return nil }

        CoverImages.remember(held, for: url)

        return held
    }
}

/// Where a spine is drawn, off the main actor and on a CoreImage context of its own, since a context
/// belongs to whoever draws with it.
private actor Press {
    static let shared = Press()

    private let context = SpinePrint.makeContext()

    func pull(_ order: SpinePrint.Order, artwork: UIImage?, density: CGFloat) -> SpinePrint.Impression {
        SpinePrint.draw(order, artwork: artwork, density: density, context: context)
    }
}
