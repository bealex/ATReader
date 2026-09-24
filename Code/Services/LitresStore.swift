//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import Litres
import UIKit

/// The reader's standing with Litres: whether they are signed in, and whether the service can be
/// reached at all from an app rather than from a browser.
///
/// The two are worth telling apart. A session can be perfectly good and still get nowhere, because the
/// service sits behind a guard that answers some clients with a challenge instead of an answer.
///
/// The session is held in memory and nowhere else. Litres is synchronised in one sitting rather than
/// watched: a reader signs in, the books come across, and there is nothing left worth keeping. A
/// credential kept past the moment it was needed is only something to lose.
@Observable @MainActor
final class LitresStore {
    private(set) var session: LitresSession?
    /// What the last look at the service found. Nothing until one has been taken.
    private(set) var reach: LitresReach?
    private(set) var isChecking = false
    /// True once the service has turned a session down, until a new one is taken. The next sign-in
    /// starts from a jar without the refused session in it.
    private(set) var wasRefused = false
    /// True where the last sign-in was closed before the service accepted a session.
    private(set) var wasAbandoned = false

    var isSignedIn: Bool { session != nil }

    @ObservationIgnored
    private lazy var client = LitresClient(configuration: Self.configuration)

    /// Sessions already put to the service during this sign-in, so the jar's repeated news of the same
    /// cookies asks once.
    @ObservationIgnored
    private var offered: Set<String> = []

    /// Takes a session off a login once the service has accepted it, and says whether it did.
    ///
    /// The site hands a visitor both halves of a session before they sign in, so a jar holding them is
    /// only a candidate until the service answers to it as a reader.
    func offer(_ found: LitresSession) async -> Bool {
        let key =
            LitresTrail.fingerprint(found.sessionId + found.superSessionId)
            + (found.userId.map { ":\($0)" } ?? "")

        guard session == nil, offered.insert(key).inserted else { return session != nil }

        LitresTrail.log(found, as: "candidate")

        guard
            found.namesAReader
        else {
            LitresTrail.memoir.info("candidate names no reader yet, waiting")
            return false
        }

        let answer = await client.reach(as: found)

        LitresTrail.memoir.info("candidate checked: \(safe: answer.summary)")

        guard answer.isSignedIn, session == nil else { return session != nil }

        session = found
        wasRefused = false
        wasAbandoned = false
        LitresTrail.memoir.info("session adopted")
        return true
    }

    /// Starts a new sign-in afresh.
    func beginSigningIn() {
        offered = []
        LitresTrail.memoir.info("sign-in opened, jar to be cleared: \(safe: wasRefused)")
    }

    /// Notes a sign-in closed by hand, which with no session taken is the other way this goes wrong.
    func abandonSigningIn() {
        guard session == nil else { return }

        wasAbandoned = true
        LitresTrail.memoir.warning("sign-in closed with no session taken")
    }

    func signOut() {
        session = nil
        reach = nil
    }

    /// Drops a session the service turned down, so the reader is asked to sign in again.
    func refuse() {
        if let session { LitresTrail.log(session, as: "refused") }

        wasRefused = true
        signOut()
    }

    /// Asks the service one harmless question and remembers what answered.
    func check() async {
        isChecking = true

        defer { isChecking = false }

        reach = await client.reach(as: session)
    }

    static let configuration: LitresClient.Configuration = {
        var configuration = LitresClient.Configuration(userAgent: userAgent)

        configuration.observe = { LitresTrail.log($0) }
        return configuration
    }()

    /// A browser's, because the guard in front of the service reads it and a stranger is turned away.
    /// The web view signs in under this too, so the session is issued to the client that will use it.
    static let userAgent = """
        Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 \
        (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36
        """
}
