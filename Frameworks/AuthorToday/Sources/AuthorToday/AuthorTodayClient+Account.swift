//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

extension AuthorTodayClient {
    /// Signs in with a password, optionally answering a two-factor challenge.
    ///
    /// When the account has a second factor the first call returns a ``LoginResult`` with no token and a
    /// ``LoginResult/twoFactorType``; call again with `code` set to the value the reader received. Passing
    /// the `trustedCode` from an earlier successful sign-in skips the challenge.
    ///
    /// On success the client adopts the token and the account id, so the caller need not wire them up.
    public func login(
        login: String,
        password: String,
        code: String? = nil,
        trustedCode: String? = nil
    ) async throws -> LoginResult {
        struct Request: Encodable {
            let login: String
            let password: String
            let code: String?
            let trustedCode: String?
        }

        let body = try Self.makeBody(Request(login: login, password: password, code: code, trustedCode: trustedCode))
        let endpoint = Endpoint(method: .post, path: "/v1/account/login-by-password", body: body)
        let result: LoginResult = try await send(endpoint)

        if let token = result.token {
            update(credentials: Credentials(token: token))
            let user = try await currentUser()
            update(credentials: Credentials(token: token, userId: user.id))
        }

        return result
    }

    /// Adopts a token kept from an earlier session and confirms it still works.
    @discardableResult
    public func restoreSession(token: String) async throws -> UserInfo {
        update(credentials: Credentials(token: token))
        let user = try await currentUser()
        update(credentials: Credentials(token: token, userId: user.id))
        return user
    }

    public func currentUser() async throws -> UserInfo {
        try await send(Endpoint(path: "/v1/account/current-user"))
    }

    /// Exchanges the current token for a fresh one; the service issues them with a short lifetime.
    @discardableResult
    public func refreshToken() async throws -> AccessToken {
        let token: AccessToken = try await send(Endpoint(method: .post, path: "/v1/account/refresh-token"))
        update(credentials: Credentials(token: token.token, userId: credentials.userId))
        return token
    }

    /// One page of the reader's library, newest activity first.
    public func userLibrary(page: Int = 1, pageSize: Int = 100) async throws -> UserLibrary {
        guard credentials.isAuthenticated else { throw AuthorTodayError.notAuthenticated }

        let endpoint = Endpoint(
            path: "/v1/account/user-library",
            query: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "pageSize", value: String(pageSize)),
            ]
        )
        return try await send(endpoint)
    }

    /// Moves works between library shelves, or removes them with ``LibraryState/none``.
    public func updateLibraryState(workIds: [Int], state: LibraryState) async throws {
        guard credentials.isAuthenticated else { throw AuthorTodayError.notAuthenticated }

        struct Request: Encodable {
            let ids: [Int]
            let state: String
        }

        let body = try Self.makeBody(Request(ids: workIds, state: state.rawValue))
        try await sendUnparsed(Endpoint(method: .post, path: "/v1/account/update-library-state", body: body))
    }
}
