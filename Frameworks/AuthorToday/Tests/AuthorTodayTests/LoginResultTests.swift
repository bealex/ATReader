//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import Testing

@testable import AuthorToday

/// The service answers `login-by-password` with two different shapes; both have to decode.
/// Payloads below are hand-written, with placeholder tokens — never captured from the service.
struct LoginResultTests {
    private func decode(_ json: String) throws -> LoginResult {
        try AuthorTodayClient.makeDecoder().decode(LoginResult.self, from: Data(json.utf8))
    }

    @Test
    func decodesAnOutstandingEmailChallenge() throws {
        let result = try decode(
            """
            {
                "twoFactorType": "Email",
                "trustedCode": null,
                "token": null,
                "issued": "0001-01-01T00:00:00Z",
                "expires": "0001-01-01T00:00:00Z",
                "twoFactorEnabled": true
            }
            """
        )

        #expect(result.requiresTwoFactor)
        #expect(result.twoFactorType == .email)
        #expect(result.token == nil)
        #expect(result.twoFactorEnabled)
    }

    /// The regression: `twoFactorType` comes back as the number `0` once no challenge is pending, and a
    /// strict decode would throw away the token in the same payload.
    @Test
    func decodesANumericTwoFactorTypeWithoutLosingTheToken() throws {
        let result = try decode(
            """
            {
                "twoFactorType": 0,
                "trustedCode": "trusted-placeholder",
                "token": "token-placeholder",
                "issued": "2026-01-02T03:04:05Z",
                "expires": "2026-01-03T03:04:05Z",
                "twoFactorEnabled": false
            }
            """
        )

        #expect(result.token == "token-placeholder")
        #expect(!result.requiresTwoFactor)
        #expect(result.twoFactorType == nil)
        #expect(result.trustedCode == "trusted-placeholder")
        #expect(!result.twoFactorEnabled)
    }

    @Test
    func decodesAnAuthenticatorChallenge() throws {
        let result = try decode(
            """
            { "twoFactorType": "Code", "token": null, "twoFactorEnabled": true }
            """
        )

        #expect(result.twoFactorType == .code)
        #expect(result.requiresTwoFactor)
    }

    @Test
    func toleratesAnUnknownTwoFactorType() throws {
        let result = try decode(
            """
            { "twoFactorType": "Telepathy", "token": null, "twoFactorEnabled": true }
            """
        )

        #expect(result.twoFactorType == .code, "an unknown challenge should fall back, not throw")
    }

    @Test
    func decodesAMinimalPayload() throws {
        let result = try decode(#"{ "token": "token-placeholder" }"#)

        #expect(result.token == "token-placeholder")
        #expect(!result.twoFactorEnabled)
        #expect(result.expires == nil)
    }
}
