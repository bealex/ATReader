//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import CryptoKit
import Foundation
import Synchronization

/// A client for the author.today mobile API (`https://api.author.today`).
///
/// The client is safe to share: the mutable part is only the credential pair, guarded by a `Mutex`.
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

    /// The token used for requests plus the account id the chapter key derivation needs.
    public struct Credentials: Sendable, Equatable {
        public var token: String?
        public var userId: Int?

        public init(token: String? = nil, userId: Int? = nil) {
            self.token = token
            self.userId = userId
        }

        public static let guest = Credentials()

        public var isAuthenticated: Bool { token != nil }

        var authorizationValue: String { "Bearer \(token ?? "guest")" }
    }

    enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
    }

    struct Endpoint: Sendable {
        var method: Method = .get
        var path: String
        var query: [URLQueryItem] = []
        var body: Data?
    }

    public let configuration: Configuration

    private let session: URLSession
    private let storage: Mutex<Credentials>

    public init(
        configuration: Configuration = .unconfigured,
        session: URLSession = .shared,
        credentials: Credentials = .guest
    ) {
        self.configuration = configuration
        self.session = session
        self.storage = Mutex(credentials)
    }

    public var credentials: Credentials { storage.withLock { $0 } }

    public func update(credentials: Credentials) {
        storage.withLock { $0 = credentials }
    }

    public func signOut() {
        storage.withLock { $0 = .guest }
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
        let (data, response) = try await session.data(for: makeRequest(endpoint))

        guard let http = response as? HTTPURLResponse else { throw AuthorTodayError.unexpectedStatus(0) }
        guard !(200 ..< 300).contains(http.statusCode) else { return data }

        if let failure = try? Self.makeDecoder().decode(Failure.self, from: data) {
            throw AuthorTodayError.api(failure.code, message: failure.message, statusCode: http.statusCode)
        }

        throw AuthorTodayError.unexpectedStatus(http.statusCode)
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
