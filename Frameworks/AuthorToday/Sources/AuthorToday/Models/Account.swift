//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// The answer to `/v1/account/login-by-password`.
///
/// A `nil` ``token`` together with a ``twoFactorType`` means the password was accepted but a second factor
/// is still outstanding — repeat the call with the code the reader received.
public struct LoginResult: Decodable, Sendable {
    public let token: String?
    public let twoFactorType: TwoFactorType?
    public let trustedCode: String?
    public let twoFactorEnabled: Bool
    public let expires: Date?

    public var requiresTwoFactor: Bool { token == nil }

    private enum CodingKeys: String, CodingKey {
        case token
        case twoFactorType
        case trustedCode
        case twoFactorEnabled
        case expires
    }

    /// The service is inconsistent about `twoFactorType`: it is the string `"Email"`/`"Code"` while a
    /// challenge is outstanding, but the number `0` once the account no longer needs one. A strict decode
    /// of the numeric form would fail the whole response — and throw away the token sitting next to it.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        token = try container.decodeIfPresent(String.self, forKey: .token)
        trustedCode = try container.decodeIfPresent(String.self, forKey: .trustedCode)
        twoFactorEnabled = try container.decodeIfPresent(Bool.self, forKey: .twoFactorEnabled) ?? false
        expires = try container.decodeIfPresent(Date.self, forKey: .expires)
        twoFactorType = (try? container.decodeIfPresent(TwoFactorType.self, forKey: .twoFactorType)) ?? nil
    }
}

/// A refreshed bearer token.
public struct AccessToken: Decodable, Sendable {
    public let token: String
    public let expires: Date?
}

/// The signed-in reader.
public struct UserInfo: Decodable, Sendable, Identifiable {
    public let id: Int
    public let userName: String?
    public let fio: String?
    public let email: String?
    public let avatarUrl: String?
    public let isBanned: Bool?
    public let emailConfirmed: Bool?

    public init(
        id: Int,
        userName: String? = nil,
        fio: String? = nil,
        email: String? = nil,
        avatarUrl: String? = nil,
        isBanned: Bool? = nil,
        emailConfirmed: Bool? = nil
    ) {
        self.id = id
        self.userName = userName
        self.fio = fio
        self.email = email
        self.avatarUrl = avatarUrl
        self.isBanned = isBanned
        self.emailConfirmed = emailConfirmed
    }

    /// The best human-facing name the profile offers.
    public var displayName: String {
        if let fio, !fio.isEmpty { return fio }
        if let userName, !userName.isEmpty { return userName }

        return String(localized: "Reader", bundle: .module)
    }

    public var avatarURL: URL? { avatarUrl.flatMap(URL.init(string:)) }
}

/// The reader's library page, with the per-shelf totals the service keeps.
public struct UserLibrary: Decodable, Sendable {
    public let worksInLibrary: [WorkMetaInfo]
    public let readingCount: Int?
    public let savedCount: Int?
    public let finishedCount: Int?
    public let purchasedCount: Int?
    public let totalCount: Int?

    public func count(for state: LibraryState) -> Int? {
        switch state {
            case .reading: readingCount
            case .saved: savedCount
            case .finished: finishedCount
            default: nil
        }
    }
}
