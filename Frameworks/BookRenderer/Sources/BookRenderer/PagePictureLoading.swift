//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import SwiftUI

/// A picture the page can draw, from wherever the app keeps its covers.
///
/// The typesetter knows how to draw one and nothing about where it is cached, which is why this is a
/// protocol rather than a call into a store.
public protocol PagePictureLoading: Sendable {
    @MainActor
    func picture(at url: URL) async -> PageImage?
}

extension EnvironmentValues {
    /// Set once, at the top of the app. A page with nothing here draws no cover, which is what a book
    /// with no artwork does anyway.
    @Entry
    public var pagePictures: (any PagePictureLoading)?
}
