//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// One cookie, kept as something that can be written down.
///
/// `HTTPCookie` is a class and carries more than is worth storing, so what the session keeps is this
/// and hands back a cookie when a request needs one.
public struct LitresCookie: Sendable, Equatable, Codable {
    public let name: String
    public let value: String
    public let domain: String
    public let path: String
    public let expiresAt: Date?
    public let isSecure: Bool

    public init(
        name: String,
        value: String,
        domain: String,
        path: String = "/",
        expiresAt: Date? = nil,
        isSecure: Bool = true
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.expiresAt = expiresAt
        self.isSecure = isSecure
    }

    public var hasExpired: Bool {
        guard let expiresAt else { return false }

        return expiresAt <= .now
    }
}

/// What a signed-in Litres session is made of.
///
/// The site hands the same session out twice over: as headers on every call to the API, and as cookies
/// on the requests that fetch a file, which go to a different host and read no headers. Both are kept,
/// because the two hosts want different ones.
public struct LitresSession: Sendable, Equatable, Codable {
    /// The session's own id. `session-id` to the API, `SID` in the cookie jar.
    public let sessionId: String
    /// The second identifier the API wants beside it, under the same name in both places.
    public let superSessionId: String
    /// Every cookie the site set, for the host that takes no headers. The guard's own are in here
    /// too, and are the reason a native client gets through at all.
    public let cookies: [LitresCookie]
    public let capturedAt: Date

    public init(sessionId: String, superSessionId: String, cookies: [LitresCookie], capturedAt: Date = .now) {
        self.sessionId = sessionId
        self.superSessionId = superSessionId
        self.cookies = cookies
        self.capturedAt = capturedAt
    }

    /// The names the session is carried under, which is what a login watches the cookie jar for.
    public enum CookieName {
        public static let session = "SID"
        public static let superSession = "supersid"
        /// A signed statement of who the session belongs to. Read for the reader's own id; it cannot
        /// be made, only kept.
        public static let context = "__Secure-session_context"
    }

    /// Reads a session out of a jar, or reports nothing where the reader has not signed in yet.
    public static func from(cookies: [LitresCookie]) -> LitresSession? {
        let named = Dictionary(cookies.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        guard
            let session = named[CookieName.session]?.value.nilWhenEmpty,
            let superSession = named[CookieName.superSession]?.value.nilWhenEmpty
        else { return nil }

        return LitresSession(sessionId: session, superSessionId: superSession, cookies: cookies)
    }

    /// Who the session belongs to, read out of the statement the site signed.
    ///
    /// The middle of a JWT, which is a fact about the session rather than a secret: the signature is
    /// what proves it, and only the site can make one.
    public var userId: Int? {
        guard let context = cookies.first(where: { $0.name == CookieName.context })?.value else { return nil }

        let parts = context.split(separator: ".")

        guard parts.count == 3, let payload = Self.base64URL(String(parts[1])) else { return nil }

        return (try? JSONDecoder().decode(Context.self, from: payload))?.userId
    }

    private struct Context: Decodable {
        let userId: Int

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
        }
    }

    private static func base64URL(_ text: String) -> Data? {
        var padded = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")

        while padded.count % 4 != 0 { padded += "=" }

        return Data(base64Encoded: padded)
    }
}

extension String {
    var nilWhenEmpty: String? { isEmpty ? nil : self }
}
