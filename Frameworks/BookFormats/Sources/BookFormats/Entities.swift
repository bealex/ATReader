//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// The character references a book's markup writes its text with.
///
/// An EPUB's XHTML names entities that only the HTML DTD ever declared, so they are resolved here
/// rather than left to a parser that would refuse the document over them.
enum Entities {
    /// Text with every character reference in it resolved. Anything unrecognised is left as written.
    static func decoded(_ text: String) -> String {
        guard text.contains("&") else { return text }

        var result = ""
        var rest = Substring(text)

        result.reserveCapacity(text.count)

        while let mark = rest.firstIndex(of: "&") {
            result += rest[rest.startIndex ..< mark]
            rest = rest[rest.index(after: mark)...]

            // A reference runs to the first semicolon, and a stray ampersand is text rather than one.
            guard
                let stop = rest.firstIndex(of: ";"),
                rest.distance(from: rest.startIndex, to: stop) <= longestName
            else {
                result.append("&")
                continue
            }

            let name = rest[rest.startIndex ..< stop]

            guard
                let character = character(named: name)
            else {
                result.append("&")
                continue
            }

            result += character
            rest = rest[rest.index(after: stop)...]
        }

        return result + rest
    }

    private static func character(named name: Substring) -> String? {
        guard !name.isEmpty else { return nil }
        guard name.hasPrefix("#") else { return named[String(name)] }

        let digits = name.dropFirst()
        let value: UInt32?

        if digits.hasPrefix("x") || digits.hasPrefix("X") {
            value = UInt32(digits.dropFirst(), radix: 16)
        } else {
            value = UInt32(digits)
        }

        return value.flatMap(Unicode.Scalar.init).map(String.init)
    }

    /// The longest name resolved here, which is what caps the search for a reference's semicolon.
    private static let longestName = 10

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}",
        "shy": "\u{00AD}", "zwj": "\u{200D}", "zwnj": "\u{200C}",
        "ndash": "–", "mdash": "—", "horbar": "―", "hellip": "…", "bull": "•", "middot": "·",
        "lsquo": "‘", "rsquo": "’", "sbquo": "‚", "ldquo": "“", "rdquo": "”", "bdquo": "„",
        "laquo": "«", "raquo": "»", "lsaquo": "‹", "rsaquo": "›", "prime": "′", "Prime": "″",
        "dagger": "†", "Dagger": "‡", "sect": "§", "para": "¶", "copy": "©", "reg": "®",
        "trade": "™", "deg": "°", "plusmn": "±", "times": "×", "divide": "÷", "minus": "−",
        "frac12": "½", "frac14": "¼", "frac34": "¾", "sup2": "²", "sup3": "³", "sup1": "¹",
        "micro": "µ", "permil": "‰", "infin": "∞", "ne": "≠", "le": "≤", "ge": "≥", "asymp": "≈",
        "larr": "←", "uarr": "↑", "rarr": "→", "darr": "↓", "harr": "↔",
        "euro": "€", "pound": "£", "yen": "¥", "cent": "¢", "curren": "¤",
        "iexcl": "¡", "iquest": "¿", "brvbar": "¦", "uml": "¨", "macr": "¯", "acute": "´",
        "cedil": "¸", "ordf": "ª", "ordm": "º", "not": "¬", "szlig": "ß",
        "agrave": "à", "aacute": "á", "acirc": "â", "atilde": "ã", "auml": "ä", "aring": "å",
        "aelig": "æ", "ccedil": "ç", "egrave": "è", "eacute": "é", "ecirc": "ê", "euml": "ë",
        "igrave": "ì", "iacute": "í", "icirc": "î", "iuml": "ï", "ntilde": "ñ",
        "ograve": "ò", "oacute": "ó", "ocirc": "ô", "otilde": "õ", "ouml": "ö", "oslash": "ø",
        "ugrave": "ù", "uacute": "ú", "ucirc": "û", "uuml": "ü", "yacute": "ý", "yuml": "ÿ",
        "Agrave": "À", "Aacute": "Á", "Acirc": "Â", "Atilde": "Ã", "Auml": "Ä", "Aring": "Å",
        "AElig": "Æ", "Ccedil": "Ç", "Egrave": "È", "Eacute": "É", "Ecirc": "Ê", "Euml": "Ë",
        "Igrave": "Ì", "Iacute": "Í", "Icirc": "Î", "Iuml": "Ï", "Ntilde": "Ñ",
        "Ograve": "Ò", "Oacute": "Ó", "Ocirc": "Ô", "Otilde": "Õ", "Ouml": "Ö", "Oslash": "Ø",
        "Ugrave": "Ù", "Uacute": "Ú", "Ucirc": "Û", "Uuml": "Ü", "Yacute": "Ý",
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "theta": "θ",
        "lambda": "λ", "mu": "μ", "pi": "π", "sigma": "σ", "phi": "φ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Pi": "Π", "Sigma": "Σ",
        "Phi": "Φ", "Omega": "Ω",
    ]
}
