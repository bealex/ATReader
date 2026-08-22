//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import CryptoKit
import Foundation
import OSLog
import Synchronization

/// A client for the author.today mobile API (`https://api.author.today`).
///
/// The client is safe to share: the mutable part is only the credential pair, guarded by a `Mutex`.
///
/// Tokens last a day. A request that fails because the token expired is retried once behind a refresh,
/// and ``credentialsDidChange`` reports every new token so the caller can persist it.
public final class AuthorTodayClient: Sendable {
    /// Host, user agent and the certificate the service binds chapter keys to.
    public struct Configuration: Sendable {
        public static let defaultBaseURL = URL(string: "https://api.author.today")!
        /// Identifies this package. Apps should pass their own instead, naming themselves.
        ///
        /// The service ignores this header entirely: every endpoint used here answers identically with
        /// any value, including none, and chapters still decrypt. It is sent only so requests are
        /// attributable.
        public static let defaultUserAgent = "AuthorToday-Swift/1.0"

        public var baseURL: URL
        public var userAgent: String

        /// The client certificate the service binds chapter keys to. **Not shipped with this package** —
        /// see `.env.example` in the repository root for what it is and where to obtain it.
        public var certificate: String

        /// The fixed salt the chapter key derivation mixes in. Supplied alongside ``certificate``.
        public var chapterSalt: String

        public init(
            certificate: String,
            chapterSalt: String,
            baseURL: URL = Configuration.defaultBaseURL,
            userAgent: String = Configuration.defaultUserAgent
        ) {
            self.certificate = certificate
            self.chapterSalt = chapterSalt
            self.baseURL = baseURL
            self.userAgent = userAgent
        }

        /// Browses, searches and lists charts, but cannot decrypt chapters.
        public static let unconfigured = Configuration(certificate: "", chapterSalt: "")

        /// False when no certificate/salt was supplied, so callers can say so plainly instead of
        /// surfacing a decryption failure.
        public var canDecryptChapters: Bool { !certificate.isEmpty && !chapterSalt.isEmpty }

        /// Sent as `X-AT-Certificate`, uppercase hex.
        ///
        /// Not authentication — a request without it still succeeds. The service binds each chapter's
        /// encryption key to whichever certificate the request claims, so omitting this yields a chapter
        /// that arrives intact and cannot be decrypted. The same certificate string, unhashed, is the
        /// last field of the key derivation in ``ChapterDecryptor``.
        var certificateHash: String? {
            guard !certificate.isEmpty else { return nil }

            return ChapterDecryptor.hexadecimal(Insecure.SHA1.hash(data: Data(certificate.utf8)))
        }
    }

    /// The token used for requests, when it runs out, and the account id the chapter key derivation needs.
    public struct Credentials: Sendable, Equatable {
        public var token: String?
        public var userId: Int?
        /// When the service said the token stops working. `nil` when it never said.
        public var expiresAt: Date?

        public init(token: String? = nil, userId: Int? = nil, expiresAt: Date? = nil) {
            self.token = token
            self.userId = userId
            self.expiresAt = expiresAt
        }

        public static let guest = Credentials()

        public var isAuthenticated: Bool { token != nil }

        /// True when the token runs out within `window`. An unknown expiry counts as expiring, so a
        /// token restored from an older build is refreshed rather than trusted.
        public func expires(within window: TimeInterval) -> Bool {
            guard isAuthenticated else { return false }
            guard let expiresAt else { return true }

            return expiresAt.timeIntervalSinceNow < window
        }

        var authorizationValue: String { "Bearer \(token ?? "guest")" }
    }

    /// Called on every credential change, including the ones the client makes for itself when it
    /// refreshes an expired token.
    public typealias CredentialsObserver = @Sendable (Credentials) -> Void

    enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
    }

    struct Endpoint: Sendable {
        var method: Method = .get
        var path: String
        var query: [URLQueryItem] = []
        var body: Data?
        /// False for the calls that mint tokens, so a failure there cannot recurse into a refresh.
        var allowsTokenRefresh = true
    }

    public let configuration: Configuration

    private let session: URLSession
    private let storage: Mutex<Credentials>
    private let observer: Mutex<CredentialsObserver?>
    private let refresh: Mutex<Task<Void, any Error>?>

    public init(
        configuration: Configuration = .unconfigured,
        session: URLSession = .shared,
        credentials: Credentials = .guest
    ) {
        self.configuration = configuration
        self.session = session
        self.storage = Mutex(credentials)
        self.observer = Mutex(nil)
        self.refresh = Mutex(nil)
    }

    public var credentials: Credentials { storage.withLock { $0 } }

    public func update(credentials: Credentials) {
        storage.withLock { $0 = credentials }
        observer.withLock { $0 }?(credentials)
    }

    /// Watches every token the client adopts, so the caller can keep its own copy current.
    public func credentialsDidChange(_ handler: CredentialsObserver?) {
        observer.withLock { $0 = handler }
    }

    public func signOut() {
        update(credentials: .guest)
    }

    func send<Response: Decodable>(_ endpoint: Endpoint) async throws -> Response {
        let data = try await sendUnparsed(endpoint)

        do {
            return try Self.makeDecoder().decode(Response.self, from: data)
        } catch {
            throw AuthorTodayError.decoding(String(describing: error))
        }
    }

    @discardableResult
    func sendUnparsed(_ endpoint: Endpoint) async throws -> Data {
        do {
            return try await perform(endpoint)
        } catch let error as AuthorTodayError where endpoint.allowsTokenRefresh && error.isTokenRejection {
            let stale = credentials.token

            guard stale != nil else { throw error }

            try await refreshCredentials(replacing: stale)
            return try await perform(endpoint)
        }
    }

    private func perform(_ endpoint: Endpoint) async throws -> Data {
        let (data, response) = try await session.data(for: makeRequest(endpoint))

        guard let http = response as? HTTPURLResponse else { throw AuthorTodayError.unexpectedStatus(0) }
        guard !(200 ..< 300).contains(http.statusCode) else { return data }

        // A refused call says why in the log, so a failure on a device can be read out of Console
        // rather than guessed at. The body is the service's own error envelope, never book text.
        Self.logger.error(
            """
            \(endpoint.method.rawValue, privacy: .public) \(endpoint.path, privacy: .public)             → \(http.statusCode, privacy: .public) \(String(bytes: data, encoding: .utf8) ?? "", privacy: .public)
            """
        )

        if let failure = try? Self.makeDecoder().decode(Failure.self, from: data) {
            throw AuthorTodayError.api(failure.code, message: failure.message, statusCode: http.statusCode)
        }

        throw AuthorTodayError.unexpectedStatus(http.statusCode)
    }

    private static let logger = Logger(subsystem: "com.lonelybytes.authortoday", category: "network")

    /// Swaps the stale token for a fresh one, collapsing everything that noticed the same expiry into
    /// one call to the service.
    func refreshCredentials(replacing staleToken: String?) async throws {
        guard credentials.token == staleToken else { return }

        let task = refresh.withLock { running -> Task<Void, any Error> in
            if let running { return running }

            let started = Task<Void, any Error> {
                defer { self.refresh.withLock { $0 = nil } }

                try await self.refreshToken()
            }
            running = started
            return started
        }

        try await task.value
    }

    private func makeRequest(_ endpoint: Endpoint) throws -> URLRequest {
        var components = URLComponents(
            url: configuration.baseURL.appendingPathComponent(endpoint.path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = endpoint.query.isEmpty ? nil : endpoint.query

        guard let url = components?.url else { throw AuthorTodayError.unexpectedStatus(0) }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        request.setValue(credentials.authorizationValue, forHTTPHeaderField: "Authorization")
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        if let certificateHash = configuration.certificateHash {
            request.setValue(certificateHash, forHTTPHeaderField: "X-AT-Certificate")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ru", forHTTPHeaderField: "Accept-Language")
        return request
    }

    private struct Failure: Decodable {
        let code: AuthorTodayError.ErrorCode
        let message: String
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)

            guard
                let date = parseDate(raw)
            else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Unrecognised date \(raw)")
                )
            }

            return date
        }
        return decoder
    }

    /// The service mixes fractional-second and whole-second stamps, with and without a zone suffix.
    private static func parseDate(_ raw: String) -> Date? {
        let strategies = [
            Date.ISO8601FormatStyle(includingFractionalSeconds: true),
            Date.ISO8601FormatStyle(includingFractionalSeconds: false),
            Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current).time(
                includingFractionalSeconds: true
            ),
            Date.ISO8601FormatStyle(includingFractionalSeconds: false, timeZone: .current).time(
                includingFractionalSeconds: false
            ),
        ]

        for strategy in strategies {
            if let date = try? strategy.parse(raw) { return date }
        }

        return nil
    }

    static func makeBody(_ value: some Encodable) throws -> Data {
        try JSONEncoder().encode(value)
    }
}
