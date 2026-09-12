//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import BookRenderer
import BookStorage
import SwiftUI

@main
struct LibrixApp: App {
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

    @State
    private var litres = LitresStore()

    @State
    private var backup = LibraryBackup()

    @State
    private var shelf = ShelfSettings()

    @State
    private var origins = BookOrigins()

    /// Hands the typesetter the picture shelf before anything asks it to set a page.
    init() {
        Renderers.connect()
    }

    var body: some Scene {
        WindowGroup {
            RootScreen.Component()
                .environment(session)
                .environment(settings)
                .environment(inbox)
                .environment(litres)
                .environment(backup)
                .environment(shelf)
                .environment(origins)
                .environment(\.pagePictures, CoverPictures())
                // Where each book came from is read once, and again whenever the shelf changes: a
                // book only arrives from somewhere by coming through the inbox.
                .task(id: inbox.importedAt) { await origins.refresh() }
                // A book whose text the device already holds under another number goes, with its
                // file: two services handing over one book left two of everything behind.
                .task {
                    guard await BookInstaller.removeDuplicates() > 0 else { return }

                    inbox.libraryChanged()
                }
                // The book a fresh install opens with, offered once. A reader who deletes it keeps it
                // deleted.
                .task { await FirstBook.offer(through: inbox) }
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
