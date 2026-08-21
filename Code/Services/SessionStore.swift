//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import Foundation
import UIKit

/// Owns the API client and the signed-in reader, and keeps the keychain in step with both.
@Observable @MainActor
final class SessionStore {
    enum State: Equatable {
        /// The stored token is being checked against the service.
        case restoring
        case signedOut
        case signedIn(UserInfo)

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
                case (.restoring, .restoring), (.signedOut, .signedOut): true
                case let (.signedIn(left), .signedIn(right)): left.id == right.id
                default: false
            }
        }
    }

    let client: AuthorTodayClient

    private(set) var state: State = .restoring

    /// True while the app is running on a token it could not confirm with the service.
    private(set) var isOffline = false

    init(client: AuthorTodayClient = SessionStore.makeClient()) {
        self.client = client
        client.credentialsDidChange { credentials in
            // The client refreshes tokens for itself, so persisting has to follow the client rather
            // than the sign-in call.
            Task { @MainActor in SessionStore.persist(credentials) }
        }
    }

    /// Builds the client from the constants `Scripts/gen-secrets.sh` wrote out of `.env`. When the
    /// build was not configured these are empty, and the app browses but cannot open chapters.
    static func makeClient() -> AuthorTodayClient {
        AuthorTodayClient(configuration: .init(
            certificate: ATSecrets.certificate,
            chapterSalt: ATSecrets.chapterSalt,
            userAgent: makeUserAgent()
        ))
    }

    /// Names this app and its version, e.g. `ATReader/1.0 (build 1; iOS 27.0)`.
    static func makeUserAgent() -> String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "ATReader/\(version) (build \(build); iOS \(UIDevice.current.systemVersion))"
    }

    /// False when this build has no service constants — the reader says so rather than failing oddly.
    var canReadChapters: Bool { ATSecrets.isConfigured }

    var user: UserInfo? {
        guard case let .signedIn(user) = state else { return nil }

        return user
    }

    var isSignedIn: Bool { user != nil }

    /// The code that lets this device skip the two-factor challenge, if the service issued one.
    var trustedCode: String? { KeychainStore.string(for: .trustedCode) }

    private static func persist(_ credentials: AuthorTodayClient.Credentials) {
        guard let token = credentials.token else { return }

        KeychainStore.store(token, for: .token)
        KeychainStore.store(credentials.expiresAt, for: .tokenExpiry)
        KeychainStore.store(credentials.userId, for: .userId)
    }

    /// Picks up the stored token and keeps it alive.
    ///
    /// The reader is signed in again before the service is asked anything, so a launch with no network
    /// still opens the library. Only a token the service actually rejects signs them out.
    func restore() async {
        guard
            let token = KeychainStore.string(for: .token)
        else {
            state = .signedOut
            return
        }

        client.update(credentials: .init(
            token: token,
            userId: KeychainStore.integer(for: .userId),
            expiresAt: KeychainStore.date(for: .tokenExpiry)
        ))

        if let cached = storedUser() { state = .signedIn(cached) }

        await refresh()
    }

    /// Renews a token close to expiry and confirms the account behind it.
    func refresh() async {
        guard KeychainStore.string(for: .token) != nil else { return }

        do {
            try await client.refreshTokenIfNeeded()
            let user = try await client.currentUser()
            KeychainStore.store(value: user, for: .user)
            KeychainStore.store(user.id, for: .userId)
            state = .signedIn(user)
            isOffline = false
        } catch let error as AuthorTodayError where error.requiresReauthentication {
            signOut()
        } catch {
            // A network that is down is not a reason to throw the session away.
            isOffline = true

            if case .restoring = state {
                state = storedUser().map(State.signedIn) ?? .signedOut
            }
        }
    }

    /// The reader as the last successful sign-in saw them, falling back to the bare account id.
    private func storedUser() -> UserInfo? {
        if let stored = KeychainStore.value(UserInfo.self, for: .user) { return stored }

        return KeychainStore.integer(for: .userId).map { UserInfo(id: $0) }
    }

    /// Signs in, returning the service's answer so the caller can drive a two-factor challenge.
    func signIn(login: String, password: String, code: String? = nil) async throws -> LoginResult {
        let result = try await client.login(
            login: login,
            password: password,
            code: code,
            trustedCode: code == nil ? trustedCode : nil
        )

        if let trusted = result.trustedCode { KeychainStore.store(trusted, for: .trustedCode) }

        guard result.token != nil else { return result }

        let user = try await client.currentUser()
        KeychainStore.store(value: user, for: .user)
        state = .signedIn(user)
        isOffline = false
        return result
    }

    func signOut() {
        client.signOut()
        KeychainStore.removeAll()
        state = .signedOut
    }
}

#if DEBUG
    extension SessionStore {
        /// Launch-argument hooks the UI tests use to reach the signed-in screens without typing credentials.
        ///
        /// `-at-ui-test-token <token>` adopts a real token; `-at-ui-test-guest` browses the catalogue with the
        /// guest token, which is enough to exercise search, the charts and the reader.
        func applyUITestOverrides(_ arguments: [String] = ProcessInfo.processInfo.arguments) async -> Bool {
            if let index = arguments.firstIndex(of: "-at-ui-test-token"), index + 1 < arguments.count {
                let token = arguments[index + 1]
                KeychainStore.store(token, for: .token)

                do {
                    let user = try await client.restoreSession(token: token)
                    state = .signedIn(user)
                } catch {
                    state = .signedOut
                }

                return true
            }

            guard arguments.contains("-at-ui-test-guest") else { return false }

            client.signOut()
            state = .signedIn(UserInfo(
                id: 0,
                userName: "guest",
                fio: "Guest",
                email: nil,
                avatarUrl: nil,
                isBanned: false,
                emailConfirmed: true
            ))
            return true
        }
    }
#endif
