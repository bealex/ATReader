//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import UIKit

/// A picture of the page the reader was on, shown at the next launch until the page itself is set.
///
/// Kept with what it was drawn for: the book, the theme and the size of the window. A launch that
/// differs in any of them shows nothing instead, since a light page under a dark one is worse than
/// bare paper.
@MainActor
enum PagePicture {
    /// What a picture has to have been drawn for to stand in for a page.
    struct Subject: Equatable {
        let workId: Int
        let theme: String
        let size: CGSize
    }

    private static let fileName = "open-page.png"

    private enum Keys {
        static let workId = "openBook.page.workId"
        static let theme = "openBook.page.theme"
        static let width = "openBook.page.width"
        static let height = "openBook.page.height"
    }

    /// Filed by name under the caches of this run: a path through the container is worthless in the next.
    private static func file(in directory: URL?) -> URL? {
        (directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)?
            .appendingPathComponent(fileName)
    }

    /// Keeps a picture and what it is of. The picture is written off the main thread, and what it is of
    /// only once it has been.
    static func keep(
        _ picture: UIImage,
        of subject: Subject,
        in defaults: UserDefaults = .standard,
        directory: URL? = nil
    ) async {
        guard let file = file(in: directory) else { return }

        forget(in: defaults, directory: directory)

        let written = await Task.detached(priority: .userInitiated) {
            guard let data = picture.pngData() else { return false }

            return (try? data.write(to: file, options: .atomic)) != nil
        }
        .value

        guard written else { return }

        defaults.set(subject.workId, forKey: Keys.workId)
        defaults.set(subject.theme, forKey: Keys.theme)
        defaults.set(Double(subject.size.width), forKey: Keys.width)
        defaults.set(Double(subject.size.height), forKey: Keys.height)
    }

    static func forget(in defaults: UserDefaults = .standard, directory: URL? = nil) {
        for key in [ Keys.workId, Keys.theme, Keys.width, Keys.height ] { defaults.removeObject(forKey: key) }

        if let file = file(in: directory) { try? FileManager.default.removeItem(at: file) }
    }

    /// What the kept picture is of, where there is one.
    static func subject(in defaults: UserDefaults = .standard) -> Subject? {
        let workId = defaults.integer(forKey: Keys.workId)

        guard workId != 0, let theme = defaults.string(forKey: Keys.theme) else { return nil }

        return Subject(
            workId: workId,
            theme: theme,
            size: CGSize(width: defaults.double(forKey: Keys.width), height: defaults.double(forKey: Keys.height))
        )
    }

    /// The kept picture, where it is of this book in this theme. Its size is the window's to check.
    static func kept(
        workId: Int,
        theme: String,
        in defaults: UserDefaults = .standard,
        directory: URL? = nil
    ) -> UIImage? {
        guard
            let subject = subject(in: defaults),
            subject.workId == workId,
            subject.theme == theme,
            let file = file(in: directory)
        else { return nil }
        guard let read = UIImage(contentsOfFile: file.path)?.cgImage, subject.size.width > 0 else { return nil }

        // A file says nothing of how many pixels stand to a point, and the window is measured in points.
        return UIImage(cgImage: read, scale: CGFloat(read.width) / subject.size.width, orientation: .up)
    }
}

/// The picture standing in for the page at launch, from the first frame until the reader has drawn.
///
/// Two things show it in turn. The root shows it while the tabs and the reader are being built, and
/// the reader takes it over once it is up and drops it when its own page is on screen.
@Observable @MainActor
final class LaunchPage {
    static let shared = LaunchPage()

    /// False once the picture has been handed on or given up.
    private var isCovering = true

    @ObservationIgnored
    private var picture: UIImage?

    @ObservationIgnored
    private var workId: Int?

    @ObservationIgnored
    private var hasLooked = false

    /// The picture for the root to show, looked for the first time it is asked: of the book this
    /// launch opens on, and drawn in the theme now in force.
    func covering(theme: String) -> UIImage? {
        look(theme: theme)

        return isCovering ? picture : nil
    }

    /// Changes nothing a view watches, since the first to ask is a view being drawn.
    private func look(theme: String) {
        guard !hasLooked else { return }

        hasLooked = true

        guard let book = OpenBook.forLaunch else { return }

        workId = book.workId
        picture = PagePicture.kept(workId: book.workId, theme: theme)

        guard picture != nil else { return }

        // A book that never opens leaves nothing to take the picture down.
        Task { [weak self] in
            try? await Task.sleep(for: Self.longestStand)
            self?.drop()
        }
    }

    /// Hands the picture to the reader of this book, which shows it from here on.
    func take(for workId: Int) -> UIImage? {
        guard workId == self.workId, let picture else { return nil }

        drop()
        return picture
    }

    func drop() {
        picture = nil
        workId = nil

        if isCovering { isCovering = false }
    }

    private static let longestStand = Duration.seconds(3)
}
