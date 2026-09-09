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

    var isSignedIn: Bool { session != nil }

    @ObservationIgnored
    private lazy var client = LitresClient(configuration: .init(userAgent: Self.userAgent))

    /// Takes a session off a login and holds it for as long as the app is running.
    func adopt(_ found: LitresSession) {
        session = found
    }

    func signOut() {
        session = nil
        reach = nil
    }

    /// Asks the service one harmless question and remembers what answered.
    func check() async {
        isChecking = true

        defer { isChecking = false }

        reach = await client.reach(as: session)
    }

    /// A browser's, because the guard in front of the service reads it and a stranger is turned away.
    /// The web view signs in under this too, so the session is issued to the client that will use it.
    static let userAgent = """
        Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 \
        (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36
        """
}
