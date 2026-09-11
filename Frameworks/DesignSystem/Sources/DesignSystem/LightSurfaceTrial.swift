//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

#if canImport(UIKit)
    import UIKit

    /// Greys the light-mode screen and card are being chosen from, picked with `-at-light-surface <n>`.
    ///
    /// Temporary: once one is chosen it becomes the two colours and this goes.
    enum LightSurfaceTrial {
        struct Tone {
            let name: String
            let screen: UIColor
            let card: UIColor
        }

        static let tones = [
            Tone(name: "0-now", screen: grey(0xF2F2F7), card: grey(0xFFFFFF)),
            Tone(name: "1-mist", screen: grey(0xE9E9EE), card: grey(0xF6F6F9)),
            Tone(name: "2-pebble", screen: grey(0xE0E0E5), card: grey(0xEFEFF3)),
            Tone(name: "3-fog", screen: grey(0xD6D6DC), card: grey(0xE7E7EC)),
            Tone(name: "4-slate", screen: grey(0xCBCBD1), card: grey(0xDDDDE3)),
            Tone(name: "5-stone", screen: grey(0xE4E1DB), card: grey(0xF1EFEA)),
            Tone(name: "6-clay", screen: grey(0xD9D5CD), card: grey(0xE9E6E0)),
        ]

        static var current: Tone {
            let asked = UserDefaults.standard.integer(forKey: "at-light-surface")

            return tones.indices.contains(asked) ? tones[asked] : tones[0]
        }

        private static func grey(_ hex: Int) -> UIColor {
            UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
    }
#endif
