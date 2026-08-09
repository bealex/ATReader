//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// Builds a usable cover URL out of the two different shapes the service returns.
///
/// `work/details` and the library hand back a full `https://cm.author.today/…` URL, already carrying
/// sizing query parameters. The catalogue hands back a bare path such as `2026/07/25/<hash>.jpg`.
/// Feeding that path straight to `URL(string:)` yields a schemeless URL that `URLSession` rejects with
/// "unsupported URL", which is why catalogue covers silently failed to load.
enum CoverURL {
    static let host = "https://cm.author.today/content/"

    /// The width asked of the service's resizer, in pixels.
    ///
    /// The CDN resizes server-side, so requesting the size actually needed turns a ~450 KB original
    /// into roughly 50 KB. Covers are drawn at most 116pt wide, so this covers a 3x screen.
    static let requestedWidth = 280

    static func absolute(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }

        // Already absolute: the service has sized it for us.
        if let direct = URL(string: raw), direct.scheme != nil { return direct }

        var components = URLComponents(string: host + raw)
        components?.queryItems = [
            URLQueryItem(name: "width", value: String(requestedWidth)),
            URLQueryItem(name: "height", value: String(requestedWidth * 3 / 2)),
            URLQueryItem(name: "rmode", value: "max"),
        ]
        return components?.url
    }
}
