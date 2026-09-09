//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import DesignSystem
import Litres
import SwiftUI

/// Signing in to Litres, and nothing else.
///
/// A web view because there is no other way: the service hands its session to a browser and signs it
/// with a key nobody else has, so the app can only let the reader sign in and take what the site puts
/// in the jar. Once it has one, this has done its job and gets out of the way.
enum LitresLoginScreen {
    struct Component: View {
        @Environment(LitresStore.self)
        private var store

        @Environment(\.dismiss)
        private var dismiss

        var body: some View {
            NavigationStack {
                LitresWebView(url: Self.signIn) { session in
                    store.adopt(session)
                    dismiss()
                }
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(Text(verbatim: "Litres"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }

        /// The reader's own books: signing in is what stands between the app and this page, so landing
        /// here is what says the session took.
        private static let signIn = URL(string: "https://www.litres.ru/my-books/")!
    }
}
