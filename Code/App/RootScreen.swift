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

        @ViewBuilder
        private var sessionRoot: some View {
            switch session.state {
                case .restoring: restoring
                case .signedOut: LoginScreen.Component()
                case .signedIn: signedIn
            }
        }

        @ViewBuilder
        private var signedIn: some View {
            #if DEBUG
                // `-at-ui-test-reader <workId>` opens straight into the reader, so the page layout can
                // be inspected without walking the tabs first. Debug builds only.
                if let workId = Self.debugReaderWorkId {
                    NavigationStack {
                        ReaderScreen.Component(workId: workId, title: "", initialChapterId: nil)
                    }
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

            private static var debugReaderWorkId: Int? {
                let arguments = ProcessInfo.processInfo.arguments

                guard
                    let index = arguments.firstIndex(of: "-at-ui-test-reader"),
                    index + 1 < arguments.count
                else { return nil }

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
