//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

#if DEBUG
    import Foundation
    import Memoirs
    import OSLog
    import QuartzCore

    /// Times one opening or shutting frame by frame, when `-at-opening-probe YES` asks for it, and logs
    /// what it found under the `opening-probe` category once the run ends.
    @MainActor
    final class OpeningProbe {
        private let opens: Bool
        private var beganAt: CFTimeInterval = 0
        private var laying: CFTimeInterval = 0
        private var lastTick: CFTimeInterval?
        private var gaps: [(gap: CFTimeInterval, open: CGFloat)] = []
        private var drawing: [CFTimeInterval] = []
        private var interval: OSSignpostIntervalState?

        /// Marks each run for Instruments, so a trace can be cut down to the runs alone.
        private static let signposter = OSSignposter(subsystem: "com.lonelybytes.atreader", category: "opening-probe")

        private static let memoir = TracedMemoir(label: "opening-probe", memoir: AppMemoir.root)

        static var isOn: Bool { UserDefaults.standard.bool(forKey: "at-opening-probe") }

        init?(opens: Bool) {
            guard Self.isOn else { return nil }

            self.opens = opens
        }

        /// The book has been laid out, which took since `start`.
        func laidOut(since start: CFTimeInterval) {
            interval = Self.signposter.beginInterval("run")
            beganAt = start
            laying = CACurrentMediaTime() - start
        }

        /// A frame of the run began at `start`, with the book `open`, and drawing it took until now.
        func ticked(at start: CFTimeInterval, open: CGFloat) {
            gaps.append((start - (lastTick ?? beganAt), open))
            drawing.append(CACurrentMediaTime() - start)
            lastTick = start
        }

        func ended() {
            if let interval { Self.signposter.endInterval("run", interval) }

            guard gaps.count > 1 else { return }

            let first = gaps[0].gap
            let steady = gaps.dropFirst().map(\.gap).sorted()
            let frame = steady[steady.count / 2]
            let late = gaps.dropFirst().filter { $0.gap > frame * Self.lateness }
            let drawn = drawing.sorted()
            let lateList = late.map { String(format: "%.1f@%.2f", $0.gap * 1_000, $0.open) }.joined(separator: " ")
            let line = String(
                format: "%@ frames %d, frame %.1f ms, laid out %.1f ms, first frame after %.1f ms, "
                    + "late %d (worst %.1f ms), draw median %.2f worst %.2f ms",
                opens ? "open" : "shut",
                gaps.count,
                frame * 1_000,
                laying * 1_000,
                first * 1_000,
                late.count,
                (late.map(\.gap).max() ?? 0) * 1_000,
                drawn[drawn.count / 2] * 1_000,
                (drawn.last ?? 0) * 1_000
            )

            Self.memoir.info("\(safe: line) | late: \(safe: lateList)")
            Self.keep("\(line) | late: \(lateList)\n")
        }

        /// Appends to `opening-probe.log` in the app's temporary folder, which outlives the log's memory.
        private static func keep(_ line: String) {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("opening-probe.log")

            guard let data = line.data(using: .utf8) else { return }

            if let handle = try? FileHandle(forWritingTo: file) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: file)
            }
        }

        /// A gap this many frames long or longer is a frame the screen showed twice.
        private static let lateness = 1.5
    }
#endif
