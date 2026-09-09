//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import Testing

@testable import Litres

/// Reading a session out of a cookie jar.
///
/// Every value here is invented. What is being checked is the shape of the thing, not anybody's session.
struct LitresSessionTests {
    private static func cookie(_ name: String, _ value: String, expiresAt: Date? = nil) -> LitresCookie {
        LitresCookie(name: name, value: value, domain: ".litres.ru", expiresAt: expiresAt)
    }

    /// A jar holds a session only once both halves of one are in it.
    @Test
    func aSessionNeedsBothOfItsHalves() {
        #expect(LitresSession.from(cookies: []) == nil)
        #expect(LitresSession.from(cookies: [ Self.cookie("SID", "abc") ]) == nil)
        #expect(LitresSession.from(cookies: [ Self.cookie("supersid", "def") ]) == nil)
    }

    @Test
    func aSessionIsReadOutOfTheJar() throws {
        let session = try #require(
            LitresSession.from(cookies: [
                Self.cookie("SID", "sessionvalue"),
                Self.cookie("supersid", "supervalue"),
                Self.cookie("_ym_uid", "analytics"),
            ])
        )

        #expect(session.sessionId == "sessionvalue")
        #expect(session.superSessionId == "supervalue")
        // The jar is kept whole, analytics and all: the guard reads its own cookies back.
        #expect(session.cookies.count == 3)
    }

    /// An empty value is no value, whatever the jar says.
    @Test
    func anEmptyHalfIsNoHalf() {
        #expect(LitresSession.from(cookies: [ Self.cookie("SID", ""), Self.cookie("supersid", "x") ]) == nil)
    }

    /// The reader's own id is stated in the middle of the signed context, which is a fact rather than
    /// a secret: the signature is what proves it.
    @Test
    func theReaderIsReadOutOfTheSignedContext() throws {
        let payload = Data(#"{"sid":"abc","user_id":4242,"auth_method":"login_or_email"}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let session = try #require(
            LitresSession.from(cookies: [
                Self.cookie("SID", "abc"),
                Self.cookie("supersid", "def"),
                Self.cookie("__Secure-session_context", "header.\(payload).signature"),
            ])
        )

        #expect(session.userId == 4242)
    }

    @Test
    func aSessionWithoutAContextNamesNobody() throws {
        let session = try #require(
            LitresSession.from(cookies: [
                Self.cookie("SID", "abc"),
                Self.cookie("supersid", "def"),
            ])
        )

        #expect(session.userId == nil)
    }

    @Test
    func aCookieKnowsWhenItIsPast() {
        #expect(Self.cookie("SID", "x", expiresAt: .now.addingTimeInterval(-60)).hasExpired)
        #expect(!Self.cookie("SID", "x", expiresAt: .now.addingTimeInterval(60)).hasExpired)
        #expect(!Self.cookie("SID", "x").hasExpired)
    }

    /// A session survives being written down and read back, which is what the keychain does to it.
    @Test
    func aSessionKeepsItselfThroughTheKeychain() throws {
        let session = try #require(
            LitresSession.from(cookies: [
                Self.cookie("SID", "abc"),
                Self.cookie("supersid", "def"),
            ])
        )
        let written = try JSONEncoder().encode(session)
        let read = try JSONDecoder().decode(LitresSession.self, from: written)

        #expect(read == session)
    }
}
