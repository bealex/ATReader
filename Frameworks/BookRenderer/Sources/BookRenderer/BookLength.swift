//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import UIKit

/// How many pages a book comes to at a setting, worked out from its length rather than by cutting it.
///
/// A page holds as many lines as its depth takes and a line as many characters of running text as its
/// measure does. A hundredth comes off for what a count of characters doesn't see: chapter openings,
/// pictures, the air between paragraphs.
public enum BookLength {
    public static func pages(characters: Int, context: ChapterLayout.Context, language: String?) -> Int {
        let style = context.style
        let perLine = context.textSize.width / advance(of: style, language: language)
        let perPage = perLine * (context.textSize.height / style.pageLine) * fullness

        guard characters > 0, perPage > 0 else { return 0 }

        return Int((Double(characters) / perPage).rounded(.up))
    }

    /// How much of a page's room running text fills.
    static let fullness: CGFloat = 0.99

    /// How wide one character of running text is at a setting, measured over a stretch of ordinary prose.
    static func advance(of style: ChapterTextStyle, language: String?) -> CGFloat {
        let sample = Typography.isRussian(language) ? russian : english
        var attributes: [NSAttributedString.Key: Any] = [ .font: style.font ]

        if style.letterSpacing != 0 { attributes[.kern] = style.letterSpacing }

        let width = (sample as NSString).size(withAttributes: attributes).width

        return max(1, width / CGFloat((sample as NSString).length))
    }

    private static let russian = """
        Утром над рекой стоял туман, и лодки у причала казались серыми тенями. Старик вышел из дома, \
        закрыл за собой калитку и медленно пошёл по тропинке к воде. Где-то далеко лаяла собака, а в \
        саду уже пели птицы, будто ничего не случилось.
        """

    private static let english = """
        In the morning a mist hung over the river, and the boats at the pier looked like grey shadows. \
        The old man came out of the house, shut the gate behind him and walked slowly down the path to \
        the water. Somewhere far off a dog was barking, and the birds were already singing in the garden.
        """
}
