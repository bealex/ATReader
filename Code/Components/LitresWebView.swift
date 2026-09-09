//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Litres
import SwiftUI
import WebKit

/// The Litres site, shown so a reader can sign in to it, and watched for the session that follows.
///
/// There is no other way in. The service hands its session out to a browser and signs it with a key
/// only the service has, so the app cannot ask for one: it can only let the reader sign in and take
/// what the site puts in the jar.
struct LitresWebView: UIViewRepresentable {
    let url: URL
    /// Called every time the jar holds a whole session. It fires more than once, since the site keeps
    /// setting cookies, so whoever takes it decides what a repeat means.
    let onSession: (LitresSession) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        // The default store, so a reader who signed in once is still signed in next time, and so the
        // session the app keeps is the one the site actually issued.
        configuration.websiteDataStore = .default()

        let view = WKWebView(frame: .zero, configuration: configuration)

        // The same one the app's own requests carry, so the session is issued to the client that will
        // use it and the guard in front of the service sees one story rather than two.
        view.customUserAgent = LitresStore.userAgent
        view.navigationDelegate = context.coordinator
        configuration.websiteDataStore.httpCookieStore.add(context.coordinator)
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onSession: onSession) }

    final class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        private let onSession: (LitresSession) -> Void

        init(onSession: @escaping (LitresSession) -> Void) {
            self.onSession = onSession
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            read(cookieStore)
        }

        func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) {
            // A page can finish without the jar changing again, and the session may already be in it.
            read(view.configuration.websiteDataStore.httpCookieStore)
        }

        private func read(_ store: WKHTTPCookieStore) {
            store.getAllCookies { [onSession] cookies in
                let kept =
                    cookies
                    .filter { $0.domain.contains("litres.ru") }
                    .map {
                        LitresCookie(
                            name: $0.name,
                            value: $0.value,
                            domain: $0.domain,
                            path: $0.path,
                            expiresAt: $0.expiresDate,
                            isSecure: $0.isSecure
                        )
                    }

                guard let session = LitresSession.from(cookies: kept) else { return }

                Task { @MainActor in onSession(session) }
            }
        }
    }
}
