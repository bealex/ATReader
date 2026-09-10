//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

#if canImport(UIKit)

    import SwiftUI
    import UIKit

    /// A file on its way to the share sheet, identified by where it is.
    public struct SharedFile: Identifiable {
        public let url: URL

        public init(url: URL) {
            self.url = url
        }

        public var id: String { url.path }
    }

    /// The system's own share sheet.
    public struct ShareSheet: UIViewControllerRepresentable {
        public let url: URL

        public init(url: URL) {
            self.url = url
        }

        public func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: [ url ], applicationActivities: nil)
        }

        public func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
    }
#endif
