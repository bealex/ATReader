//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI

@main
struct ATReaderApp: App {
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
            guard phase == .background else { return }

            BackgroundRefresh.scheduleNext()
        }
    }
}
