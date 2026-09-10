//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import SwiftUI
import UIKit

/// The app's tabs and every stack under them, owned by UIKit.
///
/// A `UITabBarController` rather than SwiftUI's `TabView`, because the bar only slides out of the way
/// as a list scrolls when UIKit is tracking that list itself. Under a `TabView` holding a collection
/// view it went in one step and came back in another.
///
/// Each tab that opens a book is a navigation controller, since a pushed screen takes the tab bar with
/// it and only a stack can say so. The profile pushes nothing full-height and keeps its own.
struct MainTabs: View {
    @Environment(SessionStore.self)
    private var session

    @Environment(ReaderSettings.self)
    private var settings

    @Environment(BookInbox.self)
    private var inbox

    @Environment(LitresStore.self)
    private var litres

    @Environment(LibraryBackup.self)
    private var backup

    @Environment(ShelfSettings.self)
    private var shelf

    @Environment(BookOrigins.self)
    private var origins

    var body: some View {
        Tabs(dressing: AppDressing(
            session: session,
            settings: settings,
            inbox: inbox,
            litres: litres,
            backup: backup,
            shelf: shelf,
            origins: origins
        ))
        .ignoresSafeArea()
    }
}

private struct Tabs: UIViewControllerRepresentable {
    let dressing: AppDressing

    /// One navigator per stack, held here so the tabs are built once and keep them.
    @MainActor
    final class Coordinator {
        let library = Navigator()
        let search = Navigator()
        let top = Navigator()
        var delegates: [NavigatorDelegate] = []
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UITabBarController {
        let tabs = UITabBarController(tabs: everyTab(context.coordinator))

        // What was wanted from the SwiftUI bar all along: it shrinks as the shelf is pulled up rather
        // than being taken away and put back.
        tabs.tabBarMinimizeBehavior = .onScrollDown

        return tabs
    }

    func updateUIViewController(_ controller: UITabBarController, context: Context) {}

    private func everyTab(_ coordinator: Coordinator) -> [UITab] {
        var tabs: [UITab] = [
            UITab(
                title: String(localized: "Library"),
                image: UIImage(systemName: "books.vertical.fill"),
                identifier: "library"
            ) { _ in
                stack(LibraryScreen.Component(), navigator: coordinator.library, in: coordinator)
            },
            // The search role is what puts search on the bar itself rather than in a field above each
            // screen, which is why the library keeps a field of its own instead.
            UISearchTab { _ in
                stack(SearchScreen.Component(), navigator: coordinator.search, in: coordinator)
            },
            UITab(
                title: String(localized: "Top"),
                image: UIImage(systemName: "chart.bar.fill"),
                identifier: "top"
            ) { _ in
                stack(TopScreen.Component(), navigator: coordinator.top, in: coordinator)
            },
            UITab(
                title: String(localized: "Profile"),
                image: UIImage(systemName: "person.crop.circle"),
                identifier: "profile"
            ) { _ in hosted(ProfileScreen.Component(), navigator: nil) },
        ]

        #if DEBUG
            // The token catalogue, drawn by the app from the tokens themselves. Its title is verbatim
            // because a token name isn't translated.
            tabs.append(UITab(title: "Design", image: UIImage(systemName: "ruler"), identifier: "design") { _ in
                hosted(NavigationStack { DesignSystemScreen.Component() }, navigator: nil)
            })
        #endif

        return tabs
    }

    /// A tab that opens books: its screen at the root of a stack of its own.
    private func stack(_ screen: some View, navigator: Navigator, in coordinator: Coordinator) -> UIViewController {
        let controller = UINavigationController(rootViewController: hosted(screen, navigator: navigator))
        let delegate = NavigatorDelegate(navigator)

        controller.navigationBar.prefersLargeTitles = true
        controller.delegate = delegate
        coordinator.delegates.append(delegate)
        navigator.drive(controller, dressing: dressing)

        return controller
    }

    private func hosted(_ screen: some View, navigator: Navigator?) -> UIViewController {
        guard let navigator else { return UIHostingController(rootView: dressing.dress(screen)) }

        return UIHostingController(rootView: dressing.dress(screen.environment(navigator)))
    }
}
