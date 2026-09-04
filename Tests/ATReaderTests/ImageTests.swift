//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import Testing
import UIKit

@testable import ATReader

/// What a picture is made of, and what the page does with it.
///
/// Every picture here is generated. The interesting cases are the ones a book actually carries: line
/// art drawn as black ink on nothing, a grey scan on white paper, and colour art that has to be left
/// alone.
@MainActor
struct ImageTests {
    /// The work id these pictures are filed under, well outside anything an import would take.
    private static let workId = LocalBooks.workId(sequence: 9999)

    // MARK: - What a picture is made of

    @Test
    func readsLineArtAsInk() async {
        let picture = await prepare(Self.lineArt(), named: "line")

        #expect(picture?.kind == .monochrome)
    }

    /// The shape a book of illustrations actually carries: one ink, and the shading in the alpha.
    @Test
    func readsInkOnNothingAsInk() async {
        let picture = await prepare(Self.transparentInk(), named: "transparent")

        #expect(picture?.kind == .monochrome)
    }

    @Test
    func readsAGreyRampAsInk() async {
        let picture = await prepare(Self.greyRamp(), named: "grey")

        #expect(picture?.kind == .monochrome)
    }

    @Test
    func readsColourArtAsColour() async {
        let picture = await prepare(Self.colourArt(), named: "colour")

        #expect(picture?.kind == .colour)
    }

    // MARK: - Drawing it

    /// Ink is drawn in the page's own colour, and where the picture was dark is where the ink lands.
    ///
    /// The stencil is the one piece of this that cannot be reasoned about from the outside: a mask read
    /// the wrong way round draws a perfect negative and nothing else complains.
    @Test
    func drawsInkInThePagesColour() async throws {
        let picture = try #require(await prepare(Self.lineArt(), named: "polarity"))
        let palette = PagePalette(foreground: .red, background: .white, isMonochrome: false)
        let drawn = draw(picture, palette: palette)

        // The generated art is dark down its left half and white down its right.
        #expect(colour(of: drawn, atX: 0.25).red > 0.5)
        #expect(colour(of: drawn, atX: 0.25).blue < 0.3)
        #expect(colour(of: drawn, atX: 0.75).blue > 0.8)
    }

    /// A picture keeps its own light and dark whatever the page is set in. Only the two colours they
    /// land on change, so a drawing is never turned into a negative of itself.
    @Test
    func keepsLightAndDarkOnADarkPage() async throws {
        let picture = try #require(await prepare(Self.lineArt(), named: "night"))
        let palette = PagePalette(foreground: .white, background: .black, isMonochrome: false)
        let drawn = draw(picture, palette: palette, on: .black)

        // The dark half takes the deeper of the page's colours and the light half the paler one, which
        // on a night page is the other way round from the light one.
        #expect(colour(of: drawn, atX: 0.25).red < 0.2)
        #expect(colour(of: drawn, atX: 0.75).red > 0.8)
    }

    /// What was never drawn on counts as light, since the paper is what shows through there.
    @Test
    func paintsWhatIsTransparentAsLight() async throws {
        let picture = try #require(await prepare(Self.transparentInk(), named: "clear"))
        let palette = PagePalette(foreground: .white, background: .black, isMonochrome: false)
        let drawn = draw(picture, palette: palette, on: .black)

        #expect(colour(of: drawn, atX: 0.25).red < 0.2)
        #expect(colour(of: drawn, atX: 0.75).red > 0.8)
    }

    /// A grey is a mixture of the two rather than one or the other.
    @Test
    func setsAGreyBetweenThePagesColours() async throws {
        let picture = try #require(await prepare(Self.greyRamp(), named: "ramp"))
        let palette = PagePalette(foreground: .black, background: .white, isMonochrome: false)
        let drawn = draw(picture, palette: palette)
        let dark = colour(of: drawn, atX: 0.15).red
        let mid = colour(of: drawn, atX: 0.5).red
        let light = colour(of: drawn, atX: 0.9).red

        #expect(dark < mid)
        #expect(mid < light)
    }

    /// Colour art is left alone until the reader asks for it in the page's colours.
    @Test
    func holdsColourArtToThePageOnlyWhenAsked() async throws {
        let picture = try #require(await prepare(Self.colourArt(), named: "held"))
        let asIs = draw(picture, palette: PagePalette(foreground: .black, background: .white, isMonochrome: false))
        let held = draw(picture, palette: PagePalette(foreground: .black, background: .white, isMonochrome: true))

        // The generated art is saturated blue down its left half.
        #expect(colour(of: asIs, atX: 0.25).blue > 0.5)
        #expect(colour(of: asIs, atX: 0.25).red < 0.3)
        #expect(colour(of: held, atX: 0.25).blue == colour(of: held, atX: 0.25).red)
    }

    /// A dark page fades colour art rather than letting it glare beside the text.
    @Test
    func fadesColourArtIntoADarkPage() async throws {
        let picture = try #require(await prepare(Self.colourArt(), named: "faded"))
        let light = draw(picture, palette: PagePalette(foreground: .black, background: .white, isMonochrome: false))
        let dark = draw(
            picture,
            palette: PagePalette(foreground: .white, background: .black, isMonochrome: false),
            on: .black
        )

        #expect(colour(of: dark, atX: 0.25).blue < colour(of: light, atX: 0.25).blue)
    }

    /// A picture is drawn the right way up, in a UIKit context and in a SwiftUI one.
    ///
    /// CoreGraphics counts upwards and both of these count down, so a picture drawn without turning the
    /// context over comes out on its head. Nothing else notices: the art is still art, upside down.
    @Test
    func drawsAPictureTheRightWayUp() async throws {
        let picture = try #require(await prepare(Self.topHeavy(), named: "upright"))
        let palette = PagePalette(foreground: .red, background: .white, isMonochrome: false)
        let uiKit = draw(picture, palette: palette)

        #expect(colour(of: uiKit, atY: 0.25).red > 0.5)
        #expect(colour(of: uiKit, atY: 0.25).blue < 0.3)
        #expect(colour(of: uiKit, atY: 0.75).blue > 0.8)

        // The title page draws its cover through a SwiftUI `Canvas`, which hands out a context of its
        // own. It is only the same way up as UIKit's by convention, so the convention is pinned here.
        let canvas = try #require(Self.render(canvasFor: picture, palette: palette))

        #expect(colour(of: canvas, atY: 0.25).red > 0.5)
        #expect(colour(of: canvas, atY: 0.25).blue < 0.3)
        #expect(colour(of: canvas, atY: 0.75).blue > 0.8)
    }

    // MARK: - How large it is set

    @Test
    func setsAPictureToTheMeasure() async throws {
        let picture = try #require(await prepare(Self.lineArt(), named: "measure"))
        let size = picture.size(fitting: 300, depth: 900)

        #expect(size.width == 300)
        #expect(abs(size.height - 300 * picture.size.height / picture.size.width) < 0.01)
    }

    /// A small picture stays small. Blown up to the measure it would be a blurred plate.
    @Test
    func neverBlowsASmallPictureUp() async throws {
        let picture = try #require(await prepare(Self.lineArt(width: 80, height: 40), named: "small"))
        let size = picture.size(fitting: 300, depth: 900)

        #expect(size.width == 80)
    }

    /// A plate deeper than the page it lands on gives up width until it fits, so it never runs off the
    /// foot of the page.
    @Test
    func holdsAPictureToTheDepthOfAPage() async throws {
        let picture = try #require(await prepare(Self.lineArt(width: 400, height: 1200), named: "tall"))
        let size = picture.size(fitting: 300, depth: 500)

        #expect(size.height == 500)
        #expect(size.width < 300)
    }

    // MARK: - On the page

    @Test
    func setsAPictureAsALineOfItsOwn() async throws {
        let source = try #require(await write(Self.lineArt(), named: "page"))
        let html = "<p>Первый абзац главы, короткий.</p><img src=\"\(source)\"><p>Второй абзац.</p>"
        let layout = await ChapterLayout.make(
            chapterId: 1,
            content: await ChapterContent.prepare(html: html),
            heading: ChapterHeading.make(position: 1, title: nil),
            context: JustificationTests.testContext
        )
        let pictures = layout.typesetLines.filter(\.isImage)

        #expect(pictures.count == 1)
        #expect(pictures.first?.width == JustificationTests.testContext.textSize.width)
    }

    /// A page holding nothing but a picture centres it, rather than hanging it from the top margin with
    /// the rest of the page empty underneath.
    @Test
    func centresAPictureThatIsTheWholePage() async throws {
        let source = try #require(await write(Self.lineArt(width: 300, height: 300), named: "alone"))
        let context = JustificationTests.testContext
        let layout = await ChapterLayout.make(
            chapterId: 1,
            content: await ChapterContent.prepare(html: "<img src=\"\(source)\">"),
            heading: ChapterHeading(),
            context: context
        )

        #expect(layout.pageCount == 1)

        let band = try #require(Self.inkBand(of: layout, context: context))
        let above = band.lowerBound - context.textRect.minY
        let below = context.textRect.maxY - band.upperBound

        #expect(above > 1)
        #expect(abs(above - below) < 2)
    }

    /// Where a picture shares the page with text, the room left over is put around the picture rather
    /// than collecting at the foot of the page.
    @Test
    func putsTheSpareRoomAroundAPicture() async throws {
        let source = try #require(await write(Self.lineArt(width: 300, height: 300), named: "shared"))
        let context = JustificationTests.testContext
        let html = "<img src=\"\(source)\"><p>Короткий абзац под иллюстрацией.</p>"
        let layout = await ChapterLayout.make(
            chapterId: 1,
            content: await ChapterContent.prepare(html: html),
            heading: ChapterHeading(),
            context: context
        )
        let band = try #require(Self.inkBand(of: layout, context: context))

        // The picture no longer starts at the top margin: it has been given air above it.
        #expect(band.lowerBound - context.textRect.minY > 1)
    }

    /// A part title is a heading and a plate and nothing else, and the chapter ends on that page. The
    /// picture is still centred in what the heading left it rather than hanging from the heading with
    /// the rest of the page empty underneath.
    @Test
    func centresAPictureUnderAHeadingThatEndsTheChapter() async throws {
        let source = try #require(await write(Self.plate(), named: "part"))
        let context = JustificationTests.testContext
        let layout = await ChapterLayout.make(
            chapterId: 1,
            content: await ChapterContent.prepare(html: "<img src=\"\(source)\">"),
            heading: ChapterHeading.make(position: 3, title: "Часть третья"),
            context: context
        )

        #expect(layout.pageCount == 1)

        let rows = Self.inkedRows(of: layout, context: context)
        // The plate runs the width of the column; the heading is a short centred line, so asking for
        // rows that are mostly ink picks out the picture and leaves the heading behind.
        let plate = try #require(Self.band(in: rows, coverage: 0.5, context: context))
        let heading = try #require(rows.indices.last { rows[$0] > 0 && CGFloat($0) < plate.lowerBound })
        let above = plate.lowerBound - CGFloat(heading + 1)
        let below = context.textRect.maxY - plate.upperBound

        #expect(below > 1)
        // Not exactly equal: the blank line under a heading stands above the picture and belongs to the
        // heading, so what is over the plate runs a little deeper than what is under it.
        #expect(abs(above - below) < 35)
    }

    /// A picture with nothing behind it takes no room, rather than leaving a gap where it would be.
    @Test
    func dropsAPictureNothingAnswersTo() async {
        let html = "<p>Первый абзац главы.</p><img src=\"nowhere/at-all.png\"><p>Второй абзац.</p>"
        let layout = await ChapterLayout.make(
            chapterId: 1,
            content: await ChapterContent.prepare(html: html),
            heading: ChapterHeading.make(position: 1, title: nil),
            context: JustificationTests.testContext
        )

        #expect(!layout.typesetLines.contains { $0.isImage })
    }

    /// Drawn art says nothing to VoiceOver, so the page names it instead of skipping over it.
    @Test
    func namesAPictureToVoiceOver() async throws {
        let source = try #require(await write(Self.lineArt(), named: "spoken"))
        let html = "<p>Первый абзац главы.</p><img src=\"\(source)\"><p>Второй абзац.</p>"
        let layout = await ChapterLayout.make(
            chapterId: 1,
            content: await ChapterContent.prepare(html: html),
            heading: ChapterHeading.make(position: 1, title: nil),
            context: JustificationTests.testContext
        )

        #expect(layout.pageText(0).contains(String(localized: "Picture.")))
        #expect(!layout.pageText(0).contains(ChapterPagination.pictureMark))
    }

    // MARK: - Reading a picture in

    private func prepare(_ image: UIImage, named name: String) async -> PageImage? {
        guard let source = await write(image, named: name) else { return nil }

        return await BookImages.shared.prepare(sources: [ source ])[source]
    }

    /// Puts a picture where a book's own would sit, so the whole path is what gets exercised.
    private func write(_ image: UIImage, named name: String) async -> String? {
        let directory = LocalBooks.imagesDirectory(workId: Self.workId)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let file = "\(name)-\(UUID().uuidString).png"

        guard
            let data = image.pngData(),
            (try? data.write(to: directory.appendingPathComponent(file))) != nil
        else { return nil }

        return LocalBooks.imageSource(workId: Self.workId, name: file)
    }

    // MARK: - Drawing one to look at

    private static let canvasSize = CGSize(width: 40, height: 40)

    private func draw(_ picture: PageImage, palette: PagePalette, on ground: UIColor = .white) -> UIImage {
        UIGraphicsImageRenderer(size: Self.canvasSize).image { drawing in
            ground.setFill()
            drawing.fill(CGRect(origin: .zero, size: Self.canvasSize))
            picture.draw(
                in: CGRect(origin: .zero, size: Self.canvasSize),
                palette: palette,
                into: drawing.cgContext
            )
        }
    }

    /// The same drawing, put through SwiftUI rather than UIKit.
    private static func render(canvasFor picture: PageImage, palette: PagePalette) -> UIImage? {
        let canvas = Canvas { context, size in
            context.withCGContext { drawing in
                picture.draw(in: CGRect(origin: .zero, size: size), palette: palette, into: drawing)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .background(Color.white)

        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        return renderer.uiImage
    }

    private func colour(
        of image: UIImage,
        atY fraction: CGFloat
    ) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        colour(of: image, at: CGPoint(x: 0.5, y: fraction))
    }

    private func colour(
        of image: UIImage,
        atX fraction: CGFloat
    ) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        colour(of: image, at: CGPoint(x: fraction, y: 0.5))
    }

    /// One pixel of a drawn picture, by where it falls across the picture.
    private func colour(of image: UIImage, at point: CGPoint) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        guard let cgImage = image.cgImage else { return (0, 0, 0) }

        var pixel: [UInt8] = [ 0, 0, 0, 0 ]
        let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        // A one-pixel window onto the picture, slid so the wanted pixel lands in it. The vertical is
        // counted from the top, the way the picture was drawn, rather than the way CoreGraphics stacks
        // its rows.
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        context?.draw(
            cgImage,
            in: CGRect(
                x: -width * point.x,
                y: -height * (1 - point.y) + 1,
                width: width,
                height: height
            )
        )

        return (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255)
    }

    /// How much of each row of a drawn page carries ink, counted in sampled pixels.
    ///
    /// The page is redrawn into a bitmap of a known shape rather than read straight out of the
    /// renderer's own: that one is wide-gamut and sixteen bits a component, where the first byte of a
    /// white pixel is zero and every row reads as covered in ink.
    private static func inkedRows(of layout: ChapterLayout, context: ChapterLayout.Context) -> [Int] {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1

        let page = UIGraphicsImageRenderer(size: context.pageSize, format: format).image { drawing in
            UIColor.white.setFill()
            drawing.fill(CGRect(origin: .zero, size: context.pageSize))
            layout.draw(page: 0)
        }

        guard let drawn = page.cgImage else { return [] }

        let width = drawn.width
        let height = drawn.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        pixels.withUnsafeMutableBytes { raw in
            let bitmap = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            bitmap?.draw(drawn, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        let sampled = Swift.stride(from: 0, to: width, by: 4)

        return (0 ..< height).map { y in
            sampled.count { pixels[y * width * 4 + $0 * 4] < 200 }
        }
    }

    /// The rows a page has ink on, taking only those covered past a share of the measure. Zero takes
    /// every mark on the page; a half takes the plates and leaves a centred line of heading behind.
    private static func inkBand(
        of layout: ChapterLayout,
        context: ChapterLayout.Context,
        coverage: CGFloat = 0
    ) -> Range<CGFloat>? {
        band(in: inkedRows(of: layout, context: context), coverage: coverage, context: context)
    }

    private static func band(in rows: [Int], coverage: CGFloat, context: ChapterLayout.Context) -> Range<CGFloat>? {
        let wanted = Int(coverage * context.textSize.width / 4)
        let inked = rows.indices.filter { rows[$0] > wanted }

        guard let top = inked.first, let bottom = inked.last else { return nil }

        return CGFloat(top) ..< CGFloat(bottom + 1)
    }

    // MARK: - Pictures to read

    /// Black down the left half, white down the right: ink on paper, inside a border of paper.
    private static func lineArt(width: CGFloat = 400, height: CGFloat = 260) -> UIImage {
        halves(width: width, height: height, left: .black, right: .white)
    }

    /// The same shape drawn as ink on nothing, which is how an illustrated book files a plate.
    private static func transparentInk() -> UIImage {
        render(width: 400, height: 260) { drawing in
            UIColor.black.withAlphaComponent(0.9).setFill()
            drawing.fill(CGRect(x: 40, y: 26, width: 160, height: 208))
        }
    }

    /// Grey through and through, which takes the page's colours the way line art does.
    private static func greyRamp() -> UIImage {
        render(width: 400, height: 260) { drawing in
            UIColor.white.setFill()
            drawing.fill(CGRect(x: 0, y: 0, width: 400, height: 260))

            for step in 0 ..< 20 {
                UIColor(white: CGFloat(step) / 20, alpha: 1).setFill()
                drawing.fill(CGRect(x: 40 + step * 16, y: 26, width: 16, height: 208))
            }
        }
    }

    /// Ink over nearly the whole of it, inside a margin of paper. A row through this one is mostly
    /// covered, which is what tells it from a line of heading standing above it.
    private static func plate() -> UIImage {
        render(width: 300, height: 300) { drawing in
            UIColor.white.setFill()
            drawing.fill(CGRect(x: 0, y: 0, width: 300, height: 300))

            UIColor.black.setFill()
            drawing.fill(CGRect(x: 30, y: 30, width: 240, height: 240))
        }
    }

    /// Dark across the top half, white across the bottom: a picture that is not the same upside down.
    private static func topHeavy() -> UIImage {
        render(width: 400, height: 260) { drawing in
            UIColor.white.setFill()
            drawing.fill(CGRect(x: 0, y: 0, width: 400, height: 260))

            UIColor.black.setFill()
            drawing.fill(CGRect(x: 40, y: 26, width: 320, height: 104))
        }
    }

    /// Saturated blue down the left half, on white.
    private static func colourArt() -> UIImage {
        halves(width: 400, height: 260, left: .systemBlue, right: .white)
    }

    /// Two blocks inside a border of paper, so the border says what the ground is without argument.
    private static func halves(width: CGFloat, height: CGFloat, left: UIColor, right: UIColor) -> UIImage {
        render(width: width, height: height) { drawing in
            UIColor.white.setFill()
            drawing.fill(CGRect(x: 0, y: 0, width: width, height: height))

            let inset = CGRect(x: width / 10, y: height / 10, width: width * 0.8, height: height * 0.8)

            left.setFill()
            drawing.fill(CGRect(x: inset.minX, y: inset.minY, width: inset.width / 2, height: inset.height))

            right.setFill()
            drawing.fill(CGRect(x: inset.midX, y: inset.minY, width: inset.width / 2, height: inset.height))
        }
    }

    /// One pixel to the point, so a picture's size in the test is the size the rule reads.
    private static func render(
        width: CGFloat,
        height: CGFloat,
        drawing: (UIGraphicsImageRendererContext) -> Void
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1

        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
            .image(actions: drawing)
    }
}
