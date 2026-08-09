//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// Every failure surfaced by ``AuthorTodayClient``.
public enum AuthorTodayError: Error, Sendable {
    /// The service answered with its own error envelope (`{ "code": …, "message": … }`).
    case api(ErrorCode, message: String, statusCode: Int)
    /// A non-2xx answer that carried no recognisable envelope.
    case unexpectedStatus(Int)
    /// The payload did not match the expected shape.
    case decoding(String)
    /// The chapter body could not be decrypted with the supplied key.
    case decryption
    /// The call needs a real account token and only a guest token is available.
    case notAuthenticated
    /// No certificate/salt was supplied, so chapters cannot be decrypted. See `.env.example`.
    case notConfigured

    /// The `code` field of the service error envelope, kept open for values we do not know yet.
    public enum ErrorCode: String, Sendable, DefaultingDecodable {
        case invalidToken = "InvalidToken"
        case invalidUsernameOrPassword = "InvalidUsernameOrPassword"
        case invalidAuthorizationScheme = "InvalidAuthorizationScheme"
        case expiredToken = "ExpiredToken"
        case internalServerError = "InternalServerError"
        case userIsBanned = "UserIsBanned"
        case userIsDeleted = "UserIsDeleted"
        case userEmailNotConfirmed = "UserEmailNotConfirmed"
        case userAccountIsDisabled = "UserAccountIsDisabled"
        case invalidRequestFields = "InvalidRequestFields"
        case chapterIsDraft = "ChapterIsDraft"
        case authorizationRequired = "AuthorizationRequired"
        case purchaseRequired = "PurchaseRequired"
        case accessOnlyForFriends = "AccessOnlyForFriends"
        case accessOnlyForSubscribers = "AccessOnlyForSubscribers"
        case notFound = "NotFound"
        case tooManyRequests = "TooManyRequests"
        case versionIsUnsupported = "VersionIsUnsupported"
        case codeNotValid = "CodeNotValid"
        case unknown = "Unknown"

        public static let fallback: Self = .unknown
    }

    /// True when the stored token is stale and the caller should sign in again.
    public var requiresReauthentication: Bool {
        switch self {
            case .notAuthenticated: true
            case let .api(code, _, _): code == .invalidToken || code == .expiredToken || code == .authorizationRequired
            default: false
        }
    }
}

extension AuthorTodayError: LocalizedError {
    public var errorDescription: String? {
        switch self {
            case let .api(_, message, _):
                message
            case let .unexpectedStatus(status):
                String(localized: "The server returned an unexpected response (\(status)).", bundle: .module)
            case let .decoding(details):
                String(localized: "Couldn’t parse the server response: \(details)", bundle: .module)
            case .decryption:
                String(localized: "Couldn’t decrypt the chapter text.", bundle: .module)
            case .notAuthenticated:
                String(localized: "You need to sign in to do that.", bundle: .module)
            case .notConfigured:
                String(
                    localized: "This build has no author.today client certificate, so chapters cannot be opened.",
                    bundle: .module
                )
        }
    }
}

/// A `String`-backed enum that decodes unknown values into a ``fallback`` case instead of throwing.
///
/// The service adds new enum members over time; a reader should keep working when it meets one.
public protocol DefaultingDecodable: RawRepresentable, Codable, Sendable where RawValue == String {
    static var fallback: Self { get }
}

extension DefaultingDecodable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? Self.fallback
    }
}
