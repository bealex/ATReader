//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import UIKit

/// The system's own dictionary, for a word taken off a page.
///
/// A reference library rather than anything of this app's: the dictionaries a reader has installed are
/// the ones they chose, and a book in Russian is read by people who have Russian ones.
struct DictionaryView: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {}
}

/// A word on its way to the dictionary. A sheet needs something it can tell apart from another.
struct LookedUpTerm: Identifiable {
    let term: String

    var id: String { term }
}
