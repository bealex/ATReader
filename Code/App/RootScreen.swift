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
                background: Color(.systemGroupedBackground)
            )
        }
    }

    struct MainTabs: View {
        var body: some View {
            TabView {
                Tab("Library", systemImage: "books.vertical.fill") {
                    LibraryScreen.Component()
                }
                // The search role is what puts search on the tab bar itself rather than in a bar above
                // each screen, which is why the library no longer carries one.
                Tab("Search", systemImage: "magnifyingglass", role: .search) {
                    SearchScreen.Component()
                }
                Tab("Top", systemImage: "chart.bar.fill") {
                    TopScreen.Component()
                }
                Tab("Profile", systemImage: "person.crop.circle") {
                    ProfileScreen.Component()
                }

                #if DEBUG
                    // The token catalogue, drawn by the app from the tokens themselves. Its label is
                    // verbatim because a token name isn't translated.
                    Tab {
                        NavigationStack { DesignSystemScreen.Component() }
                    } label: {
                        Label {
                            Text(verbatim: "Design")
                        } icon: {
                            Image(systemName: "ruler")
                        }
                    }
                #endif
            }
        }
    }
}
