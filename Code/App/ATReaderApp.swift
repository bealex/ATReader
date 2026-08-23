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

    @Environment(\.scenePhase)
    private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootScreen.Component()
                .environment(session)
                .environment(settings)
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
