//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// One page of the bundled book, set by the same packages the reader sets one with.
///
/// The reader can only be looked at through an account, a library and a book that has to be read in
/// first, which makes a picture of a page slow to take and easy to take of the wrong thing. This draws
/// the page and nothing else, so a screen size or a type size can be looked at in one launch.
@main
struct PageProofApp: App {
    var body: some Scene {
        WindowGroup { ProofPage() }
    }
}
