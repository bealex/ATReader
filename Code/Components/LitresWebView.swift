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
    /// True to drop the session cookies already in the jar before the page loads, so a session the
    /// service turned down isn't picked up again.
    var clearsSession = false
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
        #if DEBUG
            view.isInspectable = true
        #endif

        let jar = configuration.websiteDataStore.httpCookieStore
        let request = URLRequest(url: url)

        guard
            clearsSession
        else {
            jar.add(context.coordinator)
            view.load(request)
            return view
        }

        Task { @MainActor in
            await Self.forgetSession(in: jar)
            jar.add(context.coordinator)
            view.load(request)
        }
        return view
    }

    private static func forgetSession(in jar: WKHTTPCookieStore) async {
        let names: Set = [
            LitresSession.CookieName.session,
            LitresSession.CookieName.superSession,
            LitresSession.CookieName.context,
        ]
        let stale = await jar.allCookies().filter { $0.domain.contains("litres.ru") && names.contains($0.name) }

        for cookie in stale { await jar.deleteCookie(cookie) }

        LitresTrail.memoir.info("jar cleared of [\(safe: stale.map(\.name).sorted().joined(separator: ", "))]")
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
            LitresTrail.memoir.info("page finished \(safe: Self.address(view.url))")
            // A page can finish without the jar changing again, and the session may already be in it.
            read(view.configuration.websiteDataStore.httpCookieStore)
        }

        func webView(_ view: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            LitresTrail.memoir.info("page started \(safe: Self.address(view.url))")
        }

        func webView(_ view: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            LitresTrail.memoir.info("page redirected to \(safe: Self.address(view.url))")
        }

        func webView(_ view: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            LitresTrail.memoir.warning(
                "page failed \(safe: Self.address(view.url)): \(safe: error.localizedDescription)"
            )
        }

        func webView(
            _ view: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: any Error
        ) {
            LitresTrail.memoir.warning(
                "page failed \(safe: Self.address(view.url)): \(safe: error.localizedDescription)"
            )
        }

        func webView(
            _ view: WKWebView,
            decidePolicyFor response: WKNavigationResponse
        ) async -> WKNavigationResponsePolicy {
            if let http = response.response as? HTTPURLResponse, response.isForMainFrame {
                let server = http.value(forHTTPHeaderField: "Server") ?? "no server header"

                LitresTrail.memoir.info(
                    "page answered \(safe: http.statusCode) \(safe: Self.address(http.url)), \(safe: server)"
                )
            }

            return .allow
        }

        private static func address(_ url: URL?) -> String {
            url.map(LitresTrail.Redaction.scrub) ?? "no address"
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

                let names = kept.map(\.name).sorted().joined(separator: ", ")

                LitresTrail.memoir.debug("jar holds [\(safe: names)]")

                guard let session = LitresSession.from(cookies: kept) else { return }

                Task { @MainActor in onSession(session) }
            }
        }
    }
}
