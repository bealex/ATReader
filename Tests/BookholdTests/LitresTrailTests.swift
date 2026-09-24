//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import Litres
import Memoirs
import Testing

@testable import Bookhold

/// The Litres trail a reader mails off the device, which must carry nothing that signs them in.
///
/// Every login, password and address here is invented.
struct LitresTrailTests {
    private typealias Redaction = LitresTrail.Redaction

    @Test
    func queryValuesNeverLeave() throws {
        let url = try #require(URL(string: "https://www.litres.ru/auth/login/?login=zorb@example.org&pwd=hunter2#pw=x"))
        let scrubbed = Redaction.scrub(url)

        #expect(scrubbed == "https://www.litres.ru/auth/login/?login=_&pwd=_")
    }

    @Test
    func credentialsInTextAreHidden() {
        let text = #"{"login":"zorblat","password":"hunter2"} password=hunter2&next=1 email: zorb.lat@example.org"#
        let scrubbed = Redaction.scrub(text)

        #expect(!scrubbed.contains("zorblat"))
        #expect(!scrubbed.contains("hunter2"))
        #expect(!scrubbed.contains("example.org"))
        #expect(scrubbed.contains(#""password":"<hidden>""#))
        #expect(scrubbed.contains("next=1"))
    }

    @Test
    func phoneNumbersAreHidden() {
        #expect(Redaction.scrub("signed in as +7 (912) 345-67-89") == "signed in as <phone>")
        #expect(Redaction.scrub("login 89123456789 used") == "login <phone> used")
        #expect(Redaction.scrub("from +441234567890") == "from <phone>")
    }

    /// Ids, statuses and times are what the trail is for, and look like numbers too.
    @Test
    func theEvidenceIsLeftAlone() {
        let line = "02:11:05.123Z 401 art 71234567 failed, context user 123456789, age 42s"

        #expect(Redaction.scrub(line) == line)
    }

    @Test
    func aSessionIsDescribedByFingerprints() {
        let session = LitresSession(
            sessionId: "sid-zorblat-value",
            superSessionId: "super-zorblat-value",
            cookies: [
                LitresCookie(name: "SID", value: "sid-zorblat-value", domain: ".litres.ru"),
                LitresCookie(name: "supersid", value: "super-zorblat-value", domain: ".litres.ru"),
            ]
        )
        let described = LitresTrail.describe(session)

        #expect(!described.contains("zorblat"))
        #expect(described.contains("sid \(LitresTrail.fingerprint("sid-zorblat-value"))"))
        #expect(described.contains("cookies [SID, supersid]"))
        #expect(described.contains("no context"))
    }

    @Test
    func anExchangeCarriesNamesButNoValues() {
        let exchange = LitresExchange(
            url: URL(string: "https://api.litres.ru/foundation/api/users/me/arts?limit=1"),
            status: 401,
            server: "nginx",
            isPoweredByLitres: true,
            opening: #"{"error":"denied","email":"zorb@example.org"}"#,
            sentCookieNames: [ "SID", "supersid" ],
            sentSessionHeaders: true
        )
        let described = LitresTrail.describe(exchange)

        #expect(described.hasPrefix("401 https://api.litres.ru/foundation/api/users/me/arts?limit=_"))
        #expect(described.contains("sent [SID, supersid]"))
        #expect(!described.contains("example.org"))
    }

    @Test
    func theHeldTrailKeepsItsLatestLines() {
        let memoir = HeldMemoir(capacity: 3)

        for index in 1 ... 5 { memoir.info("line \(safe: index)") }

        #expect(memoir.lines.count == 3)
        #expect(memoir.lines.first?.hasSuffix("line 3") == true)
        #expect(memoir.lines.last?.hasSuffix("line 5") == true)
    }
}
