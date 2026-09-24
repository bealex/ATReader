//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import CryptoKit
import Foundation
import Litres
import Memoirs
import Synchronization
import UIKit

/// What happened while signing in to Litres and bringing books across, kept in memory for a reader to
/// send when it goes wrong.
///
/// Nothing is written to disk until the reader asks for the archive, and credentials never enter it:
/// cookie values are fingerprinted, query values dropped, and addresses and phone numbers masked.
enum LitresTrail {
    static let held = HeldMemoir(capacity: 3000)

    static let memoir = TracedMemoir(
        label: "litres.login",
        memoir: MultiplexingMemoir(memoirs: [
            held,
            AppMemoir.root,
        ])
    )

    static func log(_ session: LitresSession, as what: String) {
        memoir.info("\(safe: what): \(safe: describe(session))")
    }

    static func log(_ exchange: LitresExchange) {
        memoir.info("\(safe: describe(exchange))")
    }

    /// A session told apart from another by fingerprints, with nothing in it that would let it be used.
    static func describe(_ session: LitresSession) -> String {
        let sid = session.cookies.first { $0.name == LitresSession.CookieName.session }
        var parts = [
            "sid \(fingerprint(session.sessionId))",
            "supersid \(fingerprint(session.superSessionId))",
            "sid expires \(sid?.expiresAt.map { $0.formatted(.iso8601) } ?? "with the process")",
            "age \(Int(Date.now.timeIntervalSince(session.capturedAt)))s",
            "cookies [\(session.cookies.map(\.name).sorted().joined(separator: ", "))]",
        ]

        if let context = session.context {
            parts.append("context user \(context.userId.map(String.init) ?? "none")")
            parts.append("auth \(context.authMethod ?? "none")")
            parts.append("context sid matches \(context.sessionId == session.sessionId)")
            parts.append("context fields [\(context.fields.joined(separator: ", "))]")
        } else {
            parts.append("no context")
        }

        return parts.joined(separator: ", ")
    }

    static func describe(_ exchange: LitresExchange) -> String {
        var parts = [ "\(exchange.status) \(exchange.url.map(Redaction.scrub) ?? "no address")" ]

        if let failure = exchange.failure { parts.append("failed: \(failure)") }
        if let server = exchange.server { parts.append("server \(server)") }
        if let type = exchange.contentType { parts.append("type \(type)") }

        parts.append("litres \(exchange.isPoweredByLitres)")
        parts.append("session headers \(exchange.sentSessionHeaders)")
        parts.append("sent [\(exchange.sentCookieNames.joined(separator: ", "))]")

        if exchange.status != 200, !exchange.opening.isEmpty {
            parts.append("body \(exchange.opening.replacingOccurrences(of: "\n", with: " "))")
        }

        return Redaction.scrub(parts.joined(separator: ", "))
    }

    /// Short enough to read, long enough to tell two values apart.
    static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    /// The trail, scrubbed once more on the way out.
    @MainActor
    static func text() -> String {
        let device = UIDevice.current
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let header = [
            "Litres login trail, \(Date.now.formatted(.iso8601))",
            "Bookhold \(version) (\(build)), \(device.systemName) \(device.systemVersion), \(device.model)",
            "locale \(Locale.current.identifier), zone \(TimeZone.current.identifier)",
            "",
        ]

        return (header + held.lines.map(Redaction.scrub)).joined(separator: "\n")
    }

    /// The trail as a zip, ready to attach.
    @MainActor
    static func archive() throws -> URL {
        let stamp = Date.now.formatted(.iso8601).replacingOccurrences(of: ":", with: "")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("litres-login-\(stamp)")

        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try text().write(to: folder.appendingPathComponent("litres-login.txt"), atomically: true, encoding: .utf8)
        return try DebugReport.zipped(folder, named: "litres-login-\(stamp)")
    }

    static let recipient = "bugreport@lonelybytes.com"

    /// Strips what could identify or sign in a reader from anything written into the trail.
    enum Redaction {
        /// An address with its query values and fragment dropped, since a login can travel in either.
        static func scrub(_ url: URL) -> String {
            guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "<address>" }

            parts.user = nil
            parts.password = nil
            parts.fragment = nil
            parts.percentEncodedQueryItems = parts.percentEncodedQueryItems?.map { .init(name: $0.name, value: "_") }
            return parts.string ?? "<address>"
        }

        static func scrub(_ text: String) -> String {
            patterns.reduce(text) { text, rule in
                rule.pattern.stringByReplacingMatches(
                    in: text,
                    range: NSRange(text.startIndex..., in: text),
                    withTemplate: rule.replacement
                )
            }
        }

        private static let fields = "login|password|passwd|pwd|email|e-mail|phone|username|user_name|token|code"

        private static let patterns: [(pattern: NSRegularExpression, replacement: String)] = [
            (#""(\#(fields))"\s*:\s*"[^"]*""#, #""$1":"<hidden>""#),
            (#"(?<![\w-])(\#(fields))=[^&\s,;"]*"#, "$1=<hidden>"),
            (#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, "<email>"),
            (#"(?<![\w+])(\+7|8|7)[\s(-]*\d{3}[\s)-]*\d{3}[\s-]*\d{2}[\s-]*\d{2}(?!\w)"#, "<phone>"),
            (#"\+\d[\d\s()-]{8,16}\d"#, "<phone>"),
        ]
        .map { (try! NSRegularExpression(pattern: $0.0, options: [ .caseInsensitive ]), $0.1) }
    }
}

/// A memoir that keeps its most recent lines in memory, for a trail sent on request.
final class HeldMemoir: Memoir {
    private let state = Mutex<[String]>([])
    private let capacity: Int
    private static let markers = Output.Markers(
        verbose: "VERBOSE",
        debug: "DEBUG",
        info: "INFO",
        warning: "WARNING",
        error: "ERROR",
        critical: "CRITICAL"
    )
    private let output = Output(
        markers: markers,
        hideSensitiveValues: false,
        codePositionType: .none,
        shortTracers: true,
        separateTracers: false,
        tracerFilter: { _ in false }
    )

    init(capacity: Int) {
        self.capacity = capacity
    }

    var lines: [String] { state.withLock { $0 } }

    // swiftlint:disable:next function_parameter_count
    func append(
        _ item: MemoirItem,
        message: @autoclosure () throws -> SafeString,
        meta: @autoclosure () -> [String: SafeString]?,
        tracers: [Tracer],
        timeIntervalSinceReferenceDate: TimeInterval,
        file: String,
        function: String,
        line: UInt
    ) rethrows {
        let date = Date(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate)
        let stamp = date.formatted(.iso8601.time(includingFractionalSeconds: true))
        let parts: [String]

        switch item {
            case let .log(level):
                parts = try output.logString(
                    date: stamp,
                    level: level,
                    message: message,
                    tracers: tracers,
                    meta: meta,
                    codePosition: ""
                )
            case let .event(name):
                parts = output.eventString(date: stamp, name: name, tracers: tracers, meta: meta, codePosition: "")
            case .measurement, .tracer:
                return
        }

        let text = parts.filter { !$0.isEmpty }.joined(separator: " ")

        state.withLock {
            $0.append(text)

            if $0.count > capacity { $0.removeFirst($0.count - capacity) }
        }
    }
}
