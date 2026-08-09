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

    init(client: AuthorTodayClient = SessionStore.makeClient()) {
        self.client = client
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

    /// Adopts a token left over from an earlier launch. A rejected token is discarded silently — the
    /// reader simply lands on the sign-in screen.
    func restore() async {
        guard
            let token = KeychainStore.string(for: .token)
        else {
            state = .signedOut
            return
        }

        do {
            let user = try await client.restoreSession(token: token)
            KeychainStore.store(user.id, for: .userId)
            state = .signedIn(user)
        } catch {
            KeychainStore.remove(.token)
            KeychainStore.remove(.userId)
            client.signOut()
            state = .signedOut
        }
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

        guard let token = result.token else { return result }

        KeychainStore.store(token, for: .token)
        let user = try await client.currentUser()
        KeychainStore.store(user.id, for: .userId)
        state = .signedIn(user)
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
