//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

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

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Design.Space.extraLarge) {
                    lattice
                    palette
                    type
                    components
                }
                .padding(Design.Space.extraLarge)
            }
            .background(Design.Surface.screen)
            .navigationTitle(Text(verbatim: "Design System"))
            .navigationBarTitleDisplayMode(.inline)
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
                                .frame(width: Design.Size.markSmall, height: Design.Size.markSmall)

                            Circle()
                                .fill(Design.Surface.ground(meaning.colour))
                                .frame(width: Design.Size.markSmall, height: Design.Size.markSmall)

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
                    ForEach(Self.styles, id: \.0) { name, font in
                        VStack(alignment: .leading, spacing: Design.Space.extraSmall) {
                            Text(verbatim: name)
                                .font(Design.Style.caption)
                                .foregroundStyle(.secondary)

                            Text(verbatim: "Read the page")
                                .font(font)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }

        // MARK: - Components

        private var components: some View {
            card("Components", "The shared pieces, at the size they render, built from the tokens above.") {
                VStack(alignment: .leading, spacing: Design.Space.extraLarge) {
                    specimen("Badge") {
                        FlowLayout(spacing: Design.Space.small, lineSpacing: Design.Space.small) {
                            WorkBadge(
                                title: String(localized: "Finished"),
                                systemImage: "checkmark.circle.fill",
                                tint: Design.Palette.positive
                            )
                            WorkBadge(title: String(localized: "Ongoing"), systemImage: "pencil")
                            WorkBadge(title: nil, systemImage: "dollarsign", tint: Design.Palette.caution)
                            WorkBadge(title: "1.2K", systemImage: "heart.fill")
                        }
                    }

                    specimen("Chip") {
                        HStack(spacing: Design.Space.medium) {
                            FilterChip(title: "Selected", isSelected: true, action: {})
                            FilterChip(title: "Not selected", isSelected: false, action: {})
                        }
                    }

                    specimen("Mark") {
                        HStack(spacing: Design.Space.extraLarge) {
                            ReadingProgressRing(progress: 0.47)
                            ReadingProgressRing(progress: 1)
                            FileMark()
                            LibraryMark(inLibrary: true)
                            LibraryMark(inLibrary: false)
                        }
                    }

                    specimen("Cover, with nothing loaded") {
                        HStack(alignment: .top, spacing: Design.Space.medium) {
                            CoverImage(url: nil, width: Design.Size.rowCover, progress: 0.47, isLocal: true)
                            CoverImage(url: nil, width: Design.Size.rowCover)
                        }
                    }
                }
            }
        }

        // MARK: - Furniture

        private func card(
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

        private func specimen(_ title: String, @ViewBuilder content: () -> some View) -> some View {
            VStack(alignment: .leading, spacing: Design.Space.medium) {
                Text(verbatim: title)
                    .font(Design.Style.caption)
                    .foregroundStyle(.secondary)

                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        // MARK: - The tables themselves

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
            ("markSmall", Design.Size.markSmall),
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

        private static let styles: [(String, Font)] = [
            ("screenTitle", Design.Style.screenTitle),
            ("title", Design.Style.title),
            ("heading", Design.Style.heading),
            ("body", Design.Style.body),
            ("item", Design.Style.item),
            ("label", Design.Style.label),
            ("labelStrong", Design.Style.labelStrong),
            ("caption", Design.Style.caption),
            ("micro", Design.Style.micro),
        ]
    }
}
