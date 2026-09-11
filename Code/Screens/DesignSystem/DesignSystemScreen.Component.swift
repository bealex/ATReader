//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookKit
import DesignSystem
import SwiftUI

/// Every token in ``Design`` and every component built from them, drawn by the app itself.
///
/// A catalogue on the device is the only specimen that tells the truth: it picks up the real face, the
/// reader's Dynamic Type setting, the system's light or dark and the materials, none of which a drawing
/// of the app can. Debug builds only, and its labels are verbatim because a token name is not translated.
enum DesignSystemScreen {
    struct Component: View {
        private static let nameColumn = Design.Space.unit * 34
        private static let valueColumn = Design.Space.unit * 14
        private static let sampleCap = Design.Space.unit * 24

        /// An aside for the catalogue to hang on a point, and where on that panel it hangs.
        private struct Aside: Identifiable {
            let id = 0
            let text: String
        }

        @State
        private var highAside: Aside?

        @State
        private var lowAside: Aside?

        /// One panel with two points on it, each hanging its own aside.
        ///
        /// Two points on the same panel rather than two panels, because that is what tells a hung
        /// aside from a dropped one: an aside that ignored its point would hang from the panel's own
        /// corner, and both of these would then open in exactly the same place.
        private var calloutAnchor: some View {
            let highPoint = CGPoint(x: Design.Size.callout / 2, y: Design.Size.calloutDepth * 0.15)
            let lowPoint = CGPoint(x: Design.Size.callout / 2, y: Design.Size.calloutDepth * 0.85)
            let highBox = CGRect(origin: highPoint, size: .zero)
            let lowBox = CGRect(origin: lowPoint, size: .zero)

            return ZStack {
                Design.Surface.fill

                VStack {
                    anchorButton("Top", identifier: "catalog.callout.high") {
                        highAside = Aside(text: Self.placeholderProse)
                    }

                    Spacer()

                    anchorButton("Bottom", identifier: "catalog.callout.low") {
                        lowAside = Aside(text: Self.placeholderProse)
                    }
                }
                .padding(Design.Space.large)
            }
            .frame(width: Design.Size.callout, height: Design.Size.calloutDepth)
            .callout(over: highBox, item: $highAside, ground: Self.asideGround) { held in
                presented(held) { highAside = nil }
            }
            .callout(over: lowBox, item: $lowAside, ground: Self.asideGround) { held in
                presented(held) { lowAside = nil }
            }
        }

        /// The ground the catalogue's asides stand on, which their arrows take as well.
        private static var asideGround: Color {
            Callout<EmptyView>.surface(over: Design.Surface.card, with: .primary)
        }

        private func anchorButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
            Button(action: action) { Text(verbatim: title) }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(identifier)
        }

        private func presented(_ held: Aside, onClose: @escaping () -> Void) -> some View {
            // Titled, since what calls an aside up stands apart from what it says.
            Callout(title: "15", text: held.text, onClose: onClose)
                .accessibilityIdentifier("catalog.callout.presented")
        }

        /// The three parts of the catalogue: what the app is built from, how it moves, and what a page
        /// is set in.
        ///
        /// Apart because they answer to different rules. Everything in the app is on the lattice and
        /// takes one of the nine text roles; the reader's page is set in the face, the size and the
        /// colours whoever is reading chose, and none of that is `Design`'s to name.
        enum Segment: String, CaseIterable, Identifiable {
            case interface
            case motion
            case reader

            var id: String { rawValue }

            var title: String {
                switch self {
                    case .interface: "UI"
                    case .motion: "Motion"
                    case .reader: "Reader"
                }
            }
        }

        @State
        private var segment: Segment = .interface

        @Environment(\.dynamicTypeSize)
        private var dynamicTypeSize

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Space.extraLarge) {
                    picker

                    switch segment {
                        case .interface:
                            lattice
                            palette
                            type
                            components
                        case .motion:
                            motionSpecimens
                        case .reader:
                            readerSpecimens
                    }
                }
                .padding(Design.Space.extraLarge)
            }
            .background(Design.Surface.screen)
            .navigationTitle(Text(verbatim: "Design System"))
            .navigationBarTitleDisplayMode(.inline)
        }

        private var picker: some View {
            Picker(selection: $segment) {
                ForEach(Segment.allCases) { Text(verbatim: $0.title).tag($0) }
            } label: {
                Text(verbatim: "Catalogue")
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("catalog.segment")
        }

        // MARK: - Lattice

        private var lattice: some View {
            card("Lattice", "Every length is a multiple of three. The hairline is a device pixel, not a measurement.") {
                VStack(alignment: .leading, spacing: Design.Space.medium) {
                    group("Space")

                    ForEach(Self.spaces, id: \.0) { name, value in
                        measure(name, value) {
                            Capsule()
                                .fill(Design.Palette.accent)
                                .frame(width: value, height: Design.Space.small)
                        }
                    }

                    group("Radius")

                    ForEach(Self.radii, id: \.0) { name, value in
                        measure(name, value) {
                            RoundedRectangle(cornerRadius: value)
                                .strokeBorder(Design.Palette.accent, lineWidth: Design.Stroke.hairline * 2)
                                .frame(width: Self.sampleCap, height: Design.Space.huge)
                        }
                    }

                    group("Stroke")

                    ForEach(Self.strokes, id: \.0) { name, value in
                        measure(name, value) {
                            Capsule()
                                .fill(Design.Palette.accent)
                                .frame(width: Self.sampleCap, height: value)
                        }
                    }

                    group("Size")

                    ForEach(Self.sizes, id: \.0) { name, value in
                        measure(name, value) {
                            RoundedRectangle(cornerRadius: Design.Radius.small)
                                .fill(Design.Surface.ground(Design.Palette.accent))
                                .frame(width: min(value, Self.sampleCap * 2), height: min(value, Design.Space.huge))
                        }
                    }
                }
            }
        }

        // MARK: - Palette

        private var palette: some View {
            card("Palette", "Five colours carry a fact. Anything else on screen is a system surface or label.") {
                VStack(alignment: .leading, spacing: Design.Space.medium) {
                    group("Meaning")

                    ForEach(Self.meanings) { meaning in
                        HStack(spacing: Design.Space.medium) {
                            Text(verbatim: meaning.name)
                                .font(Design.Style.label)
                                .frame(width: Self.nameColumn, alignment: .leading)

                            Circle()
                                .fill(meaning.colour)
                                .frame(width: Design.Size.mark, height: Design.Size.mark)

                            Circle()
                                .fill(Design.Surface.ground(meaning.colour))
                                .frame(width: Design.Size.mark, height: Design.Size.mark)

                            Text(verbatim: meaning.usage)
                                .font(Design.Style.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    group("Surface")

                    ForEach(Self.surfaces, id: \.0) { name, colour in
                        HStack(spacing: Design.Space.medium) {
                            Text(verbatim: name)
                                .font(Design.Style.label)
                                .frame(width: Self.nameColumn, alignment: .leading)

                            RoundedRectangle(cornerRadius: Design.Radius.small)
                                .fill(colour)
                                .frame(width: Self.sampleCap, height: Design.Space.huge)
                                .overlay {
                                    RoundedRectangle(cornerRadius: Design.Radius.small)
                                        .strokeBorder(Design.Surface.edge, lineWidth: Design.Stroke.hairline)
                                }

                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }

        // MARK: - Type

        private var type: some View {
            card("Type", "Nine roles, each one system text style, so every one of them follows Dynamic Type.") {
                VStack(alignment: .leading, spacing: Design.Space.medium) {
                    ForEach(Self.styles, id: \.name) { role in
                        VStack(alignment: .leading, spacing: Design.Space.extraSmall) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(verbatim: role.name)

                                Spacer()

                                Text(verbatim: Self.measured(role, at: dynamicTypeSize))
                                    .monospacedDigit()
                            }
                            .font(Design.Style.caption)
                            .foregroundStyle(.secondary)

                            Text(verbatim: "Read the page")
                                .font(role.font)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }

        // MARK: - Components

        private var components: some View {
            card(
                "Components",
                "Every shared piece, at the size it renders. Two are missing on purpose: the loading "
                    + "overlay fills a screen, and the share sheet is the system's own."
            ) {
                VStack(alignment: .leading, spacing: Design.Space.extraLarge) {
                    specimen("Badge") {
                        FlowLayout(spacing: Design.Space.small, lineSpacing: Design.Space.small) {
                            Pill(
                                title: "Finished",
                                systemImage: "checkmark.circle.fill",
                                tint: Design.Palette.positive,
                                label: "Finished"
                            )
                            Pill(title: "Ongoing", systemImage: "pencil", label: "Ongoing")
                            Pill(
                                title: nil,
                                systemImage: "dollarsign",
                                tint: Design.Palette.caution,
                                label: "Costs money"
                            )
                            Pill(title: "1.2K", systemImage: "heart.fill", label: "1.2K")
                        }
                    }

                    specimen("Action") {
                        VStack(spacing: Design.Space.medium) {
                            Button {
                            } label: {
                                Label {
                                    Text(verbatim: "Continue reading")
                                } icon: {
                                    Image(systemName: "book.fill")
                                }
                                .actionLabel()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Button(role: .destructive) {
                            } label: {
                                Label {
                                    Text(verbatim: "Delete this book")
                                } icon: {
                                    Image(systemName: "trash")
                                }
                                .actionLabel()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    specimen("Bar glyph") {
                        HStack(spacing: Design.Space.medium) {
                            ForEach(Self.barGlyphs, id: \.self) { name in
                                Button {
                                } label: {
                                    Image(systemName: name).barGlyph()
                                }
                            }
                        }
                    }

                    specimen("Chip") {
                        HStack(spacing: Design.Space.medium) {
                            FilterChip(title: "Selected", isSelected: true, hint: "", action: {})
                            FilterChip(title: "Not selected", isSelected: false, hint: "", action: {})
                        }
                    }

                    specimen("Mark") {
                        // Wrapped rather than one row: a row of every mark runs wider than a phone, and
                        // the whole catalogue then stands wider than the screen and loses both edges.
                        FlowLayout(spacing: Design.Space.extraLarge, lineSpacing: Design.Space.large) {
                            // The two pairs worth telling apart: nothing read from barely read,
                            // and nearly finished from finished.
                            ProgressMark(progress: 0, isComplete: false, ground: .artwork)
                            ProgressMark(progress: 0.01, isComplete: false, ground: .artwork)
                            ProgressMark(progress: 0.47, isComplete: false, ground: .artwork)
                            // The pair worth telling apart at a glance.
                            ProgressMark(progress: 0.99, isComplete: false, ground: .artwork)
                            ProgressMark(progress: 1, isComplete: true, ground: .artwork)
                            ProgressMark(progress: 0.47, isComplete: false)
                            SourceMark(origin: .service)
                            SourceMark(origin: .litres)
                            SourceMark(origin: .file)
                            OngoingMark()
                            LibraryMark(inLibrary: true)
                            LibraryMark(inLibrary: false)
                        }
                    }

                    // A glyph is not text, and a row aligned on the baseline lines an image up by
                    // its bottom edge. The first line here is what that looks like; the second is the
                    // same glyph set as one, which is what belongs in a row.
                    specimen("Baseline: a glyph sits on the line only when it is set as one") {
                        VStack(alignment: .leading, spacing: Design.Space.large) {
                            RowStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(Design.Style.caption)
                                SeriesNumber(number: 3)
                                Text(verbatim: "Image, off the line")
                                    .font(Design.Style.label)
                            }

                            RowStack {
                                LineGlyph(systemImage: "checkmark.circle.fill")
                                    .font(Design.Style.caption)
                                SeriesNumber(number: 3)
                                Text(verbatim: "LineGlyph, on it")
                                    .font(Design.Style.label)
                            }
                        }
                    }

                    specimen("Series number") {
                        RowStack(spacing: Design.Space.medium) {
                            ForEach([ 1, 7, 14 ], id: \.self) { SeriesNumber(number: $0) }
                        }
                    }

                    // Every line here should read as one line. A badge or a pill that hangs below the
                    // words beside it, or floats above them, is the thing this specimen is for.
                    specimen("Baseline: a row sets everything on one line") {
                        VStack(alignment: .leading, spacing: Design.Space.large) {
                            RowStack {
                                SeriesNumber(number: 3)
                                Text(verbatim: "Title, in the title role").font(Design.Style.title)
                            }

                            RowStack {
                                SeriesNumber(number: 12)
                                Text(verbatim: "Heading, the role a row wears").font(Design.Style.heading)
                            }

                            RowStack {
                                SeriesNumber(number: 7)
                                Text(verbatim: "Label, the role a quiet row wears").font(Design.Style.label)
                            }

                            // The folded run on the shelf: two numbers and the gap between them.
                            RowStack {
                                SeriesNumber(number: 1)
                                Text(verbatim: "…").font(Design.Style.label).foregroundStyle(.tertiary)
                                SeriesNumber(number: 17)
                            }

                            RowStack(spacing: Design.Space.medium) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(Design.Style.caption)
                                    .foregroundStyle(.tint)
                                SeriesNumber(number: 4)
                                Text(verbatim: "Glyph, badge, words and pill").font(Design.Style.label)
                                Pill(title: "Ongoing", systemImage: "pencil", label: "Ongoing")
                            }
                        }
                    }

                    specimen("Row") {
                        VStack(alignment: .leading, spacing: Design.Space.extraLarge) {
                            BookRow(work: Self.placeholder, number: 3, shortTitle: "Long Winter")
                            RankedRow(rank: 2, work: Self.placeholder)
                        }
                    }

                    // Shown twice on purpose. In the column an aside is handed a width and any layout
                    // would look right; hung on a point it has to find its way to that point, which is
                    // the half that went wrong.
                    specimen("Callout") {
                        VStack(alignment: .leading, spacing: Design.Space.large) {
                            Callout(text: Self.placeholderProse)
                                .accessibilityIdentifier("catalog.callout")

                            // Tap the panel to hang one on the dot. The way this fails is by hanging
                            // in the top corner instead, where a popover has no room and is clipped.
                            calloutAnchor
                        }
                    }

                    // The card and its pointer are one path, which is what keeps them one colour and
                    // lets one shadow be cast by both.
                    specimen("Callout shape") {
                        RowStack(spacing: Design.Space.large) {
                            ForEach([ true, false ], id: \.self) { down in
                                CalloutShape(pointerX: Design.Size.mark, pointsDown: down)
                                    .fill(Design.Surface.fill)
                                    .frame(width: Design.Size.callout / 2, height: Design.Size.mark * 3)
                            }
                        }
                    }

                    specimen("Expandable text") {
                        ExpandableText(Self.placeholderProse, lineLimit: 2)
                    }

                    specimen("Disclosure row") {
                        DisclosureLabel {
                            Label {
                                Text(verbatim: "Opens a screen")
                            } icon: {
                                Image(systemName: "textformat.size")
                            }
                        }
                    }

                    specimen("Loading card") {
                        LoadingCard(title: "Building the chart…", label: "Loading top books")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Design.Space.medium)
                            .background(Design.Surface.screen, in: .rect(cornerRadius: Design.Radius.medium))
                    }

                    specimen("Cover, with nothing loaded") {
                        HStack(alignment: .top, spacing: Design.Space.medium) {
                            CoverImage(
                                url: nil,
                                width: Design.Size.rowCover,
                                progress: 0.47,
                                origin: .litres,
                                isOngoing: true
                            )
                            CoverImage(url: nil, width: Design.Size.rowCover, origin: .service)
                            CoverImage(url: nil, width: Design.Size.rowCover)
                        }
                    }
                }
            }
        }

        // MARK: - Furniture

        func card(
            _ title: String,
            _ subtitle: String,
            @ViewBuilder content: () -> some View
        ) -> some View {
            VStack(alignment: .leading, spacing: Design.Space.small) {
                Text(verbatim: title)
                    .font(Design.Style.heading)

                Text(verbatim: subtitle)
                    .font(Design.Style.caption)
                    .foregroundStyle(.secondary)

                content()
                    .padding(.top, Design.Space.medium)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Design.Space.large)
            .background(Design.Surface.card, in: .rect(cornerRadius: Design.Radius.medium))
        }

        private func group(_ title: String) -> some View {
            Text(verbatim: title.uppercased())
                .font(Design.Style.micro)
                .foregroundStyle(.tertiary)
                .padding(.top, Design.Space.small)
        }

        private func measure(_ name: String, _ value: CGFloat, @ViewBuilder sample: () -> some View) -> some View {
            HStack(spacing: Design.Space.medium) {
                Text(verbatim: name)
                    .font(Design.Style.label)
                    .frame(width: Self.nameColumn, alignment: .leading)

                Text(verbatim: Double(value).formatted(.number.precision(.fractionLength(0 ... 1))))
                    .font(Design.Style.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: Self.valueColumn, alignment: .trailing)

                sample()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        func specimen(_ title: String, @ViewBuilder content: () -> some View) -> some View {
            VStack(alignment: .leading, spacing: Design.Space.medium) {
                Text(verbatim: title)
                    .font(Design.Style.caption)
                    .foregroundStyle(.secondary)

                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        // MARK: - The tables themselves

        /// Invented, and obviously so. Nothing the service returned ever goes in the repository.
        private static let placeholder = Book(
            id: 1,
            title: "Title of the book, long enough that it runs to a second line",
            authorLine: "Author Name",
            coverURL: nil,
            annotation: nil,
            seriesTitle: "Name of the series",
            likeCount: 1200,
            isFinished: false,
            readingProgress: 0.47,
            hasStartedReading: true
        )

        private static let placeholderProse = """
            A blurb runs to a few lines and then stops, and the control below opens the rest of it \
            where there is more to read than the limit allows.
            """

        private static let barGlyphs = [
            "checklist", "plus", "line.3.horizontal.decrease.circle", "ellipsis.circle",
        ]

        private static let spaces: [(String, CGFloat)] = [
            ("extraSmall", Design.Space.extraSmall),
            ("small", Design.Space.small),
            ("medium", Design.Space.medium),
            ("large", Design.Space.large),
            ("extraLarge", Design.Space.extraLarge),
            ("huge", Design.Space.huge),
            ("section", Design.Space.section),
        ]

        private static let radii: [(String, CGFloat)] = [
            ("small", Design.Radius.small),
            ("medium", Design.Radius.medium),
            ("large", Design.Radius.large),
        ]

        private static let strokes: [(String, CGFloat)] = [
            ("hairline", Design.Stroke.hairline),
            ("ring", Design.Stroke.ring),
        ]

        private static let sizes: [(String, CGFloat)] = [
            ("markSmall", Design.Size.mark),
            ("mark", Design.Size.mark),
            ("control", Design.Size.control),
            ("touch", Design.Size.touch),
            ("avatar", Design.Size.avatar),
            ("rowCover", Design.Size.rowCover),
            ("cover", Design.Size.cover),
            ("coverLarge", Design.Size.coverLarge),
        ]

        /// One of the five, and the kind of fact it carries.
        private struct Meaning: Identifiable {
            let name: String
            let colour: Color
            let usage: String

            var id: String { name }
        }

        private static let meanings = [
            Meaning(name: "accent", colour: Design.Palette.accent, usage: "Theirs to act on"),
            Meaning(name: "positive", colour: Design.Palette.positive, usage: "Finished"),
            Meaning(name: "caution", colour: Design.Palette.caution, usage: "In the way"),
            Meaning(name: "alert", colour: Design.Palette.alert, usage: "Wrong"),
            Meaning(name: "neutral", colour: Design.Palette.neutral, usage: "Just a fact"),
        ]

        private static let surfaces: [(String, Color)] = [
            ("screen", Design.Surface.screen),
            ("card", Design.Surface.card),
            ("fill", Design.Surface.fill),
        ]

        /// A text role, and the system style and weight it is built from, which is where its size is read.
        private struct Role {
            let name: String
            let font: Font
            let textStyle: UIFont.TextStyle
            let isBold: Bool
        }

        private static let styles = [
            Role(name: "screenTitle", font: Design.Style.screenTitle, textStyle: .largeTitle, isBold: true),
            Role(name: "title", font: Design.Style.title, textStyle: .title3, isBold: true),
            Role(name: "heading", font: Design.Style.heading, textStyle: .headline, isBold: false),
            Role(name: "item", font: Design.Style.item, textStyle: .callout, isBold: false),
            Role(name: "label", font: Design.Style.label, textStyle: .subheadline, isBold: false),
            Role(name: "caption", font: Design.Style.caption, textStyle: .caption1, isBold: false),
            Role(name: "micro", font: Design.Style.micro, textStyle: .caption2, isBold: false),
        ]

        /// A role's size and weight at the reader's Dynamic Type setting, read off the font UIKit gives
        /// that style rather than written down beside it.
        private static func measured(_ role: Role, at size: DynamicTypeSize) -> String {
            let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
            var font = UIFont.preferredFont(forTextStyle: role.textStyle, compatibleWith: traits)

            if role.isBold, let bold = font.fontDescriptor.withSymbolicTraits(.traitBold) {
                font = UIFont(descriptor: bold, size: font.pointSize)
            }

            let traitsOfFont = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
            let weight = (traitsOfFont?[.weight] as? CGFloat) ?? 0
            let points = Double(font.pointSize).formatted(.number.precision(.fractionLength(0 ... 1)))

            return "\(points) pt, \(weightName(weight))"
        }

        private static func weightName(_ weight: CGFloat) -> String {
            let names: [(UIFont.Weight, String)] = [
                (.ultraLight, "ultralight"), (.thin, "thin"), (.light, "light"), (.regular, "regular"),
                (.medium, "medium"), (.semibold, "semibold"), (.bold, "bold"), (.heavy, "heavy"), (.black, "black"),
            ]

            return names.min { abs($0.0.rawValue - weight) < abs($1.0.rawValue - weight) }?.1 ?? "regular"
        }
    }
}
