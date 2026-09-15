//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import DesignSystem
import SwiftUI

/// Decides between the sign-in screen and the signed-in tabs.
enum RootScreen {
    struct Component: View {
        @Environment(SessionStore.self)
        private var session

        @Environment(ReaderSettings.self)
        private var settings

        @Environment(\.scenePhase)
        private var phase

        var body: some View {
            Group {
                #if DEBUG
                    if Self.showsDesignSystem {
                        NavigationStack { DesignSystemScreen.Component() }
                    } else {
                        sessionRoot
                    }
                #else
                    sessionRoot
                #endif
            }
            .animation(.default, value: session.state)
            // Not from this view's own colour scheme: the reader holds the window to the page's light
            // or dark while a book is open, and every view in it then answers with the page.
            .onChange(of: phase, initial: true) { _, now in
                guard now == .active else { return }

                settings.readTheSystem()
            }
            // And once the view is in a window, since a scene asked for before there is one answers
            // nothing and the phase would not change again until the app had been away.
            .onAppear { settings.readTheSystem() }
            .task {
                guard case .restoring = session.state else { return }

                #if DEBUG
                    if await session.applyUITestOverrides() { return }
                #endif

                await session.restore()
            }
        }

        /// The library opens whether or not anyone has signed in. A reader with books of their own has
        /// no account to give, and signing in is offered from the profile instead of demanded at the
        /// door.
        @ViewBuilder
        private var sessionRoot: some View {
            switch session.state {
                case .restoring: restoring
                case .signedOut, .signedIn: tabs
            }
        }

        @ViewBuilder
        private var tabs: some View {
            #if DEBUG
                // `-at-ui-test-reader <workId>` opens straight into the reader, so the page layout can
                // be inspected without walking the tabs first. Debug builds only.
                if let workId = Self.debugReaderWorkId {
                    NavigationStack {
                        ReaderScreen.Component(workId: workId, title: "", initialChapterId: Self.debugReaderChapterId)
                    }
                    // The reader pushes and presents like any screen, and there is no tab under this
                    // one to have handed it a navigator.
                    .environment(Navigator())
                } else {
                    MainTabs()
                }
            #else
                MainTabs()
            #endif
        }

        #if DEBUG
            /// `-at-design-system YES` opens the catalogue without signing in, since the design system
            /// has nothing to do with having an account.
            private static var showsDesignSystem: Bool {
                UserDefaults.standard.bool(forKey: "at-design-system")
            }

            private static var debugReaderWorkId: Int? { debugArgument("-at-ui-test-reader") }

            /// `-at-ui-test-chapter <id>` says which chapter to open, so a picture of a page can be of
            /// one with text on it rather than of the title page every book opens on.
            private static var debugReaderChapterId: Int? { debugArgument("-at-ui-test-chapter") }

            private static func debugArgument(_ name: String) -> Int? {
                let arguments = ProcessInfo.processInfo.arguments

                guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }

                return Int(arguments[index + 1])
            }
        #endif

        private var restoring: some View {
            LoadingOverlay(
                title: "Restoring your session…",
                label: "Restoring your session",
                background: Design.Surface.screen
            )
        }
    }
}
