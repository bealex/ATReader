//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import QuartzCore
import Testing
import UIKit

@testable import Bookhold

/// What the book opening off its cover costs the main thread: laying it out, taking in the page before,
/// and each frame of the run, committed as the screen would commit it.
@MainActor
struct OpeningFrameCostTests {
    @Test
    func openingAccountsForItsFrames() throws {
        let window = try #require(Self.window())
        let container = UIView(frame: window.bounds)
        let page = UIView(frame: container.bounds)
        let cover = CGRect(x: 40, y: 200, width: 90, height: 135)
        let picture = Self.picture(size: cover.size)
        let words = Self.words
        var asked = 0

        page.backgroundColor = .white
        window.addSubview(container)
        container.addSubview(page)
        defer { container.removeFromSuperview() }

        CATransaction.flush()

        var book: OpeningBook?
        let laying = Self.time {
            book = OpeningBook(
                page: page,
                in: container,
                cover: cover,
                picture: picture,
                paper: .white,
                read: 0.6,
                pageBefore: OpeningBook.PageBefore(
                    isReady: {
                        asked += 1
                        return asked > Self.framesBeforePageArrives
                    },
                    face: { nil },
                    draw: { context in
                        UIGraphicsPushContext(context)
                        Self.draw(words, in: container.bounds.size)
                        UIGraphicsPopContext()
                    }
                )
            )
            CATransaction.flush()
        }
        let opening = try #require(book)
        var frames: [Duration] = []

        for frame in 0 ... Self.frames {
            frames.append(Self.time {
                opening.draw(open: CGFloat(frame) / CGFloat(Self.frames))
                CATransaction.flush()
            })
        }

        let arrival = frames[Self.framesBeforePageArrives]
        var steady = frames
        steady.remove(at: Self.framesBeforePageArrives)
        steady.sort()

        Self.say(
            """
            opening, \(Self.frames) frames:
              laid out in \(Self.show(laying))
              frame the page before arrives \(Self.show(arrival))
              other frames: median \(Self.show(steady[steady.count / 2])), \
            90th \(Self.show(steady[steady.count * 9 / 10])), worst \(Self.show(steady.last ?? .zero))
              all frames \(Self.show(frames.reduce(.zero, +)))
            """
        )
    }

    /// One run at 120 Hz.
    private static let frames = 102
    private static let framesBeforePageArrives = 10

    private static func window() -> UIWindow? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene?.windows.first ?? scene.map { UIWindow(windowScene: $0) }

        window?.isHidden = false
        return window
    }

    private static func time(_ work: () -> Void) -> Duration {
        let start = ContinuousClock.now

        work()
        return start.duration(to: .now)
    }

    /// A made-up cover: a gradient and a block of colour.
    private static func picture(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { drawn in
            UIColor.systemTeal.setFill()
            drawn.fill(CGRect(origin: .zero, size: size))
            UIColor.systemOrange.setFill()
            drawn.fill(CGRect(x: 10, y: 20, width: size.width - 20, height: size.height / 3))
        }
    }

    /// A made-up page of text, drawn as the reader draws a sheet: the words alone, the paper left clear.
    private static let words = (0 ..< 400).map { String(repeating: "lorem", count: 1 + $0 % 3) }.joined(separator: " ")

    private static func draw(_ words: String, in size: CGSize) {
        (words as NSString).draw(
            in: CGRect(origin: .zero, size: size).insetBy(dx: 20, dy: 60),
            withAttributes: [ .font: UIFont.systemFont(ofSize: 18) ]
        )
    }

    private static func show(_ duration: Duration) -> String {
        let micro = duration.components.attoseconds / 1_000_000_000_000 + duration.components.seconds * 1_000_000

        return String(format: "%.2f ms", Double(micro) / 1_000)
    }

    private static func say(_ line: String) {
        print(line)

        guard let data = "\(line)\n".data(using: .utf8) else { return }

        let path = FileManager.default.temporaryDirectory.appendingPathComponent("opening-frames.log")

        try? data.write(to: path)
    }
}
