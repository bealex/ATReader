//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

/// Decides between the sign-in screen and the signed-in tabs.
enum RootScreen {
    struct Component: View {
        @Environment(SessionStore.self)
        private var session

        var body: some View {
            Group {
                switch session.state {
                    case .restoring: restoring
                    case .signedOut: LoginScreen.Component()
                    case .signedIn: signedIn
                }
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
        @State
        private var navigator = Navigator()

        var body: some View {
            @Bindable var navigator = navigator

            NavigationStack(path: $navigator.path) {
                tabs
                    .navigationDestination(for: AppRoute.self) { AppRouteDestination(route: $0) }
            }
            .environment(navigator)
        }

        private var tabs: some View {
            TabView {
                Tab("Library", systemImage: "books.vertical.fill") {
                    LibraryScreen.Component()
                }
                Tab("Top", systemImage: "chart.bar.fill") {
                    TopScreen.Component()
                }
                Tab("Profile", systemImage: "person.crop.circle") {
                    ProfileScreen.Component()
                }
            }
        }
    }
}
