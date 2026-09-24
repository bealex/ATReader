//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import Testing

@testable import Litres

/// Telling a refused session from a guard standing in front of the service.
struct LitresRefusalTests {
    private static let page = "<!DOCTYPE html><html><head><title>zorblat</title></head>"

    @Test
    func theServiceTurningTheSessionDownIsARefusal() {
        let reply = LitresExchange(status: 401, contentType: "application/json", isPoweredByLitres: true, opening: "{}")

        #expect(LitresClient.refusal(of: reply, host: .api) == .unauthorised)
    }

    /// The guard answers 403 as well, and without the service's own header.
    @Test
    func theGuardIsNeverTakenForARefusal() {
        let guarded = LitresExchange(status: 403, server: "ddos-guard", opening: Self.page)
        let unmarked = LitresExchange(status: 403, opening: "{}")

        #expect(LitresClient.refusal(of: guarded, host: .api) == .guarded)
        #expect(LitresClient.refusal(of: unmarked, host: .api) == .guarded)
        #expect(LitresClient.refusal(of: guarded, host: .site) == .guarded)
    }

    @Test
    func aPageInPlaceOfAFileIsAChallenge() {
        let reply = LitresExchange(status: 200, server: "nginx", opening: "  " + Self.page)

        #expect(LitresClient.refusal(of: reply, host: .site) == .guarded)
    }

    @Test
    func theSiteRefusingAFileIsARefusal() {
        let reply = LitresExchange(status: 403, server: "nginx", opening: "PK\u{3}\u{4}")

        #expect(LitresClient.refusal(of: reply, host: .site) == .unauthorised)
    }

    @Test
    func anAnswerIsNoRefusal() {
        let api = LitresExchange(status: 200, isPoweredByLitres: true, opening: "{}")
        let site = LitresExchange(status: 200, opening: "PK\u{3}\u{4}")

        #expect(LitresClient.refusal(of: api, host: .api) == nil)
        #expect(LitresClient.refusal(of: site, host: .site) == nil)
    }

    @Test
    func anyOtherStatusIsCarriedThrough() {
        let reply = LitresExchange(status: 502, isPoweredByLitres: true, opening: "{}")

        #expect(LitresClient.refusal(of: reply, host: .api) == .service(status: 502))
    }
}
