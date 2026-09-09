//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookRenderer
import DesignSystem
import SwiftUI
import UIKit

/// The half of the catalogue that answers to the reader rather than to `Design`.
///
/// Every specimen here is set by the book's own typesetter, so what is shown is what a page would do:
/// its breaking, its hyphenation, its filling. Nothing here is on the lattice, and nothing here takes
/// one of the nine text roles, because a page belongs to whoever is reading it.
extension DesignSystemScreen.Component {
    var readerSpecimens: some View {
        VStack(alignment: .leading, spacing: Design.Space.extraLarge) {
            card(
                "Russian",
                "Justified by default: the dictionary is good and the words are long enough to fill a line."
            ) {
                VStack(alignment: .leading, spacing: Design.Space.large) {
                    specimen("Justified") {
                        ReaderSpecimen(text: Self.russian, style: Self.style(justified: true))
                    }

                    specimen("Ragged right") {
                        ReaderSpecimen(text: Self.russian, style: Self.style(justified: false))
                    }
                }
            }

            card("English", "Ragged right by default: a justified narrow column of short words pulls them apart.") {
                VStack(alignment: .leading, spacing: Design.Space.large) {
                    specimen("Justified") {
                        ReaderSpecimen(text: Self.english, style: Self.style(justified: true))
                    }

                    specimen("Ragged right") {
                        ReaderSpecimen(text: Self.english, style: Self.style(justified: false))
                    }
                }
            }

            card("Sizes", "The same setting at the sizes a reader is most likely to choose.") {
                VStack(alignment: .leading, spacing: Design.Space.large) {
                    ForEach(Self.sizes, id: \.self) { size in
                        specimen("\(Int(size)) points") {
                            ReaderSpecimen(text: Self.russian, style: Self.style(justified: true, size: size))
                        }
                    }
                }
            }

            card("Picked out", "What the reader has drawn a finger across, painted under the words.") {
                specimen("Selection") {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: Design.Radius.small)
                            .fill(Design.Surface.picked(.primary))
                            .frame(width: Design.Size.callout / 2, height: Design.Space.section)

                        ReaderSpecimen(text: Self.russian, style: Self.style(justified: true))
                    }
                }
            }

            card("Aside", "A note or a picked phrase, in the page's own colours rather than the app's.") {
                specimen("Callout") {
                    Callout(title: "[15]", text: Self.aside, foreground: .primary, background: Design.Surface.card)
                        .accessibilityIdentifier("catalog.reader.callout")
                }
            }
        }
    }

    /// What a page is set in here. Not `Design`'s to name: on a real page these come from the reader.
    private static func style(justified: Bool, size: Double = 19) -> ChapterTextStyle {
        ChapterTextStyle(
            face: .serif,
            weight: .regular,
            fontSize: size,
            lineSpacing: size * 0.35,
            letterSpacing: 0,
            justifiesRussian: justified,
            justifiesEnglish: justified,
            textColor: .label,
            backgroundColor: .systemBackground,
            monochromeImages: false,
            indentsParagraphs: false
        )
    }

    private static let sizes: [Double] = [ 15, 19, 24 ]

    /// Written for the catalogue. Nothing a book ever said goes in this repository.
    private static let russian = """
        Дом стоял на краю деревни, и дорога от него уходила прямо в лес. Утром там было тихо, только \
        ветер качал верхушки старых сосен. Мальчик вышел за ворота, посмотрел на небо и пошёл вниз по \
        тропинке, где вода в реке была холодной, а на другом берегу начинался густой туман.
        """

    private static let english = """
        The house stood at the edge of the village, and the road from it ran straight into the wood. \
        In the morning it was quiet there, and the wind moved only the tops of the older pines. The \
        boy went out through the gate, looked at the sky, and started down the path towards the river.
        """

    private static let aside = """
        A note is the book's own words, so it is set the way the page is and only a shade smaller.
        """
}

/// One passage, set to whatever width it is given.
///
/// It measures itself rather than being told, because the typesetter needs a measure before it can
/// break a single line and the catalogue's cards are as wide as the screen happens to be.
private struct ReaderSpecimen: View {
    let text: String
    let style: ChapterTextStyle

    @State
    private var width: CGFloat = 0

    var body: some View {
        Group {
            if width > 0 {
                BookTextView(text: text, style: style, width: width)
            } else {
                Color.clear.frame(height: style.fontSize * 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { width = $0 })
    }
}
