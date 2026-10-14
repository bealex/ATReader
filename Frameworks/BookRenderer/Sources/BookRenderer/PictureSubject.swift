//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import CoreGraphics
import CoreImage
import Foundation
import Vision

/// Where a picture's subject stands: the figures, creatures and machines a dark page keeps as drawn
/// while the rest of the picture is turned over.
///
/// Found by Vision's foreground model, then cut back to the subject's own outline. The model's edge
/// falls in the paper just outside the ink, and that strip would stay pale while the paper beyond it
/// went dark: a white outline round every figure.
enum PictureSubject {
    /// What looking for a picture's subject came to.
    enum Outcome: Sendable {
        /// The subject, as a grey mask the size of the picture: white where it stands.
        case found(CGImage)
        /// The model looked and found nothing to keep.
        case nothing
        /// The model couldn't look, as in the simulator, which has none.
        case unavailable
    }

    /// The subject of a picture given as its darkness, white for ink.
    static func look(darkness: CGImage) -> Outcome {
        guard let ink = levels(of: darkness) else { return .unavailable }

        return look(light: ink.map { 255 - $0 }, width: darkness.width, height: darkness.height)
    }

    /// The subject looked for in a picture at its own size, with only the mask scaled to `width` by
    /// `height`: a picture shrunk first loses the line the edge is cut back to.
    static func look(original: CGImage, scaledTo width: Int, height: Int) -> Outcome {
        let shrink = min(1, Double(largest) / Double(max(original.width, original.height)))
        let ownWidth = max(1, Int((Double(original.width) * shrink).rounded()))
        let ownHeight = max(1, Int((Double(original.height) * shrink).rounded()))

        guard
            let light = levels(of: original, width: ownWidth, height: ownHeight, onWhite: true)
        else {
            return .unavailable
        }

        let outcome = look(light: light, width: ownWidth, height: ownHeight)

        guard case let .found(mask) = outcome else { return outcome }

        return scaled(mask, width: width, height: height).map(Outcome.found) ?? .unavailable
    }

    /// The longest side a picture is looked at, past which even the original is shrunk first.
    private static let largest = 4096

    private static func look(light: [UInt8], width: Int, height: Int) -> Outcome {
        guard
            width > 0,
            height > 0,
            let paper = greyImage(light, width: width, height: height)
        else {
            return .unavailable
        }
        guard let looked = foreground(of: softened(paper), width: width, height: height) else { return .unavailable }
        guard let found = looked else { return .nothing }

        let whole = withEnclosedPaper(found, light: light, width: width, height: height)
        let kept = cutToTheInk(whole, light: light, width: width, height: height)

        guard
            let mask = greyImage(softened(kept, width: width, height: height), width: width, height: height)
        else {
            return .unavailable
        }

        return .found(mask)
    }

    // MARK: - The model

    /// How far the copy the model sees is blurred, in pixels: hatching and open strokes read as the
    /// tone and shape they draw, and the model takes in more of a figure.
    private static let softening = 1.5

    /// The picture as the model sees it. Only the model: the cut to the ink reads the sharp picture.
    private static func softened(_ picture: CGImage) -> CGImage {
        let extent = CGRect(x: 0, y: 0, width: picture.width, height: picture.height)
        let blurred = CIImage(cgImage: picture)
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [ kCIInputRadiusKey: softening ])
            .cropped(to: extent)

        return CIContext().createCGImage(blurred, from: extent) ?? picture
    }

    /// Vision's foreground mask for a picture drawn dark on light, top row first: nil inside where it
    /// found nothing, and nil outside where it couldn't look.
    private static func foreground(of picture: CGImage, width: Int, height: Int) -> [Bool]?? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: picture)

        guard (try? handler.perform([ request ])) != nil else { return nil }
        guard let result = request.results?.first else { return .some(nil) }
        guard
            let buffer = try? result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        else { return nil }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard
            CVPixelBufferGetWidth(buffer) == width,
            CVPixelBufferGetHeight(buffer) == height,
            let base = CVPixelBufferGetBaseAddress(buffer)
        else { return nil }

        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let isFloat = CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float
        var inside = [Bool](repeating: false, count: width * height)

        for y in 0 ..< height {
            let row = base.advanced(by: y * rowBytes)

            for x in 0 ..< width {
                let level = isFloat
                    ? row.assumingMemoryBound(to: Float.self)[x]
                    : Float(row.assumingMemoryBound(to: UInt8.self)[x]) / 255

                if level >= 0.5 { inside[y * width + x] = true }
            }
        }

        return inside.contains(true) ? .some(inside) : .some(nil)
    }

    // MARK: - Putting back what the drawing shuts in

    /// What counts as ink when looking for paper the drawing shuts in.
    private static let ink: UInt8 = 128

    /// Gaps in an outline this many pixels across are closed first, since line art leaves them.
    private static let sealing = 2

    /// How near the subject a shut-in patch of paper has to stand, in pixels, and how much of it.
    private static let nearness = 6
    private static let nearShare = 0.3

    /// The subject with every patch of paper the drawing shuts in beside it put back.
    ///
    /// The model misses parts of a figure it doesn't recognise as one: a face drawn in profile with
    /// open strokes comes back as a notch in the mask. The drawing says otherwise, since the face is
    /// paper inside its own outline. A patch of paper that no path from the picture's edge reaches
    /// without crossing ink, and that stands mostly against the subject, joins it.
    private static func withEnclosedPaper(_ inside: [Bool], light: [UInt8], width: Int, height: Int) -> [Bool] {
        let count = width * height
        let sealed = grown(light.map { $0 < ink }, by: sealing, width: width, height: height)
        let near = grown(inside, by: nearness, width: width, height: height)
        var patch = [Int32](repeating: 0, count: count)
        var added = [Bool](repeating: false, count: count)
        var queue = [Int](), members = [Int]()
        var next: Int32 = 0

        for start in 0 ..< count where !sealed[start] && patch[start] == 0 {
            next += 1
            patch[start] = next
            queue = [ start ]
            members.removeAll(keepingCapacity: true)

            var head = 0, touchesEdge = false

            while head < queue.count {
                let index = queue[head]
                head += 1
                members.append(index)

                let x = index % width, y = index / width

                if x == 0 || y == 0 || x == width - 1 || y == height - 1 { touchesEdge = true }

                forEachNeighbour(of: index, width: width, height: height) { neighbour in
                    guard !sealed[neighbour], patch[neighbour] == 0 else { return }

                    patch[neighbour] = next
                    queue.append(neighbour)
                }
            }

            guard !touchesEdge, members.count > 30, members.count < count / 4 else { continue }

            let alreadyIn = members.count { inside[$0] }
            let beside = members.count { near[$0] }

            guard
                Double(alreadyIn) < 0.95 * Double(members.count),
                Double(beside) >= nearShare * Double(members.count)
            else { continue }

            for index in members { added[index] = true }
        }

        // Grown back over the sealing, so a patch meets the ink itself rather than stopping short of it.
        let reaching = grown(added, by: sealing, width: width, height: height)

        return (0 ..< count).map { inside[$0] || (reaching[$0] && light[$0] >= ink) }
    }

    /// A mask grown outwards by `steps` pixels, one neighbour at a time.
    private static func grown(_ mask: [Bool], by steps: Int, width: Int, height: Int) -> [Bool] {
        var current = mask

        for _ in 0 ..< steps {
            var next = current

            for index in 0 ..< current.count where current[index] {
                forEachNeighbour(of: index, width: width, height: height) { next[$0] = true }
            }

            current = next
        }

        return current
    }

    // MARK: - Cutting the edge back to the ink

    /// Anything lighter than the core of a line is paper, its soft grey edge included, so the subject
    /// ends at the ink itself and leaves no grey fringe on the dark side.
    private static let paper: UInt8 = 60

    /// How deep into the subject the outside may eat, against the picture's shorter side: about as wide
    /// as the strip of paper the model leaves outside the ink. Line art draws faces with open strokes,
    /// and a deeper band runs in through the gaps and takes the face out of the subject.
    private static let band = 0.006

    /// The subject less the paper the outside reaches through paper alone, within a band at its edge.
    private static func cutToTheInk(_ inside: [Bool], light: [UInt8], width: Int, height: Int) -> [Bool] {
        let count = width * height
        let deepest = max(2, Int((band * Double(min(width, height))).rounded()))
        var depth = [Int32](repeating: -1, count: count)
        var queue = [Int32]()

        queue.reserveCapacity(count)

        for index in 0 ..< count where !inside[index] {
            depth[index] = 0
            queue.append(Int32(index))
        }

        // How many steps each pixel of the subject stands from the outside, as far as the band reaches.
        var head = 0

        while head < queue.count {
            let index = Int(queue[head])
            head += 1

            let next = depth[index] + 1

            guard next <= deepest else { continue }

            forEachNeighbour(of: index, width: width, height: height) { neighbour in
                guard depth[neighbour] < 0 else { return }

                depth[neighbour] = next
                queue.append(Int32(neighbour))
            }
        }

        // The paper in the band that the outside reaches without crossing ink.
        var reached = [Bool](repeating: false, count: count)

        queue.removeAll(keepingCapacity: true)

        for index in 0 ..< count where !inside[index] { queue.append(Int32(index)) }

        head = 0

        while head < queue.count {
            let index = Int(queue[head])
            head += 1

            forEachNeighbour(of: index, width: width, height: height) { neighbour in
                guard
                    inside[neighbour],
                    !reached[neighbour],
                    depth[neighbour] >= 0,
                    light[neighbour] >= paper
                else { return }

                reached[neighbour] = true
                queue.append(Int32(neighbour))
            }
        }

        return (0 ..< count).map { inside[$0] && !reached[$0] }
    }

    private static func forEachNeighbour(of index: Int, width: Int, height: Int, _ body: (Int) -> Void) {
        let x = index % width

        if x > 0 { body(index - 1) }
        if x < width - 1 { body(index + 1) }
        if index >= width { body(index - width) }
        if index < width * (height - 1) { body(index + width) }
    }

    /// The kept pixels as levels, each one the share of its own three-by-three neighbourhood kept, so
    /// the edge is not stepped.
    private static func softened(_ kept: [Bool], width: Int, height: Int) -> [UInt8] {
        var levels = [UInt8](repeating: 0, count: width * height)

        for y in 0 ..< height {
            for x in 0 ..< width {
                var total = 0, counted = 0

                for dy in -1 ... 1 {
                    let row = y + dy

                    guard row >= 0, row < height else { continue }

                    for dx in -1 ... 1 {
                        let column = x + dx

                        guard column >= 0, column < width else { continue }

                        counted += 1

                        if kept[row * width + column] { total += 1 }
                    }
                }

                levels[y * width + x] = UInt8(total * 255 / counted)
            }
        }

        return levels
    }

    // MARK: - Bytes

    /// A mask drawn again at another size.
    private static func scaled(_ mask: CGImage, width: Int, height: Int) -> CGImage? {
        guard mask.width != width || mask.height != height else { return mask }
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        else { return nil }

        context.interpolationQuality = .high
        context.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// A picture's grey levels at `width` by `height`, one byte a pixel, top row first; laid on white
    /// first where asked, so what was never drawn on reads as paper.
    private static func levels(of image: CGImage, width: Int? = nil, height: Int? = nil, onWhite: Bool = false)
        -> [UInt8]?
    {
        let width = width ?? image.width, height = height ?? image.height
        var bytes = [UInt8](repeating: onWhite ? 255 : 0, count: width * height)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                )
            else { return false }

            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        return drawn ? bytes : nil
    }

    private static func greyImage(_ bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
