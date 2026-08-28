//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

@main
struct ATReaderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    @State
    private var session = SessionStore()

    @State
    private var settings = ReaderSettings()

    @State
    private var inbox = BookInbox.shared

    @Environment(\.scenePhase)
    private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootScreen.Component()
                .environment(session)
                .environment(settings)
                .environment(inbox)
                // A book handed over by another app. The library screen may not exist yet, so the
                // reading-in happens away from it and the shelf picks the book up afterwards.
                .onOpenURL { url in
                    Task { await inbox.accept(url) }
                }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.taskIdentifier)) {
            await BackgroundRefresh.runSweep(session: session)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
                case .background: BackgroundRefresh.scheduleNext()
                // Tokens last a day, so coming back to the app is the moment to renew one.
                case .active: Task { await session.refresh() }
                default: break
            }
        }
    }
}
