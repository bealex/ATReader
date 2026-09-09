//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

public enum LitresError: Error, Sendable, Equatable, CustomStringConvertible {
    case notSignedIn
    case guarded
    case unauthorised
    case service(status: Int)
    /// What arrived could not be read, and what went wrong reading it. Said rather than counted: a
    /// bare "malformed" is what turned two hundred and fifty-six different books into one number.
    case malformed(String)

    /// Said in words, because the numbering behind a Swift error tells nobody anything: an enum
    /// reports the case's own index and orders the ones carrying a value first, so a plain refusal
    /// arrives as "error 0" with the status it came with thrown away.
    public var description: String {
        switch self {
            case .notSignedIn: "not signed in"
            case .guarded: "answered by the guard rather than the service"
            case .unauthorised: "the session was refused"
            case let .service(status): "the service answered \(status)"
            case let .malformed(why): "the answer could not be read: \(why)"
        }
    }
}

/// What a request met on the way in.
///
/// The site sits behind a guard that answers some clients with a challenge page instead of the thing
/// they asked for. A browser gets through because it carries the guard's own cookies; whether this app
/// does is the first thing worth knowing, since nothing else can be built until it does.
public struct LitresReach: Sendable, Equatable {
    public let status: Int
    /// True where what came back was the API answering rather than a page standing in front of it.
    public let isService: Bool
    /// True where the guard answered instead.
    public let isGuarded: Bool
    /// What the session was worth, where the API answered at all.
    public let isSignedIn: Bool
    public let server: String?
    /// The opening of the body, for a report when none of the above explains it.
    public let opening: String

    public var summary: String {
        if isGuarded { return "guarded (\(status), \(server ?? "no server header"))" }
        if !isService { return "not the service (\(status), \(server ?? "no server header"))" }

        return isSignedIn ? "open, signed in (\(status))" : "open, signed out (\(status))"
    }
}

/// Talks to Litres over the same two hosts its own site does.
///
/// The API takes the session as headers; the host that hands out files takes it as cookies and reads no
/// headers at all. One client covers both so the difference is stated once.
public final class LitresClient: Sendable {
    public struct Configuration: Sendable {
        public var api = URL(string: "https://api.litres.ru")!
        public var site = URL(string: "https://www.litres.ru")!
        /// Which of the service's own apps this claims to be. The site's own web build sends 115.
        public var appId = "115"
        public var language = "ru"
        public var currency = "RUB"
        /// A browser's, because the guard in front of the service reads it.
        public var userAgent: String

        public init(userAgent: String) {
            self.userAgent = userAgent
        }
    }

    public let configuration: Configuration
    private let session: URLSession
    private let pace = Pace()

    public init(configuration: Configuration, session: URLSession? = nil) {
        self.configuration = configuration
        self.session = session ?? URLSession(configuration: Self.transport())
    }

    /// Holds every request a moment apart from the one before it.
    ///
    /// A native client asking as fast as it can is what gets a session challenged, and there is nothing
    /// to be won by hurrying: a library is brought across once, in the background, and a reader is
    /// waiting on the downloads rather than on this.
    private actor Pace {
        private var previous: ContinuousClock.Instant?
        private let gap: Duration = .milliseconds(400)

        func wait() async {
            defer { previous = .now }

            guard let previous else { return }

            let since = ContinuousClock.now - previous

            guard since < gap else { return }

            try? await Task.sleep(for: gap - since)
        }
    }

    /// Cookies are carried by hand rather than by a shared jar, so nothing this app does leaks into
    /// another part of it and a signed-out reader is signed out everywhere at once.
    private static func transport() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral

        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.waitsForConnectivity = true
        return configuration
    }

    // MARK: - Getting in at all

    /// Asks the service one harmless question and reports what answered.
    ///
    /// The reader's own books, because that answers all three questions at once: whether the guard let
    /// this through, whether the API is there, and whether the session is worth anything.
    public func reach(as session: LitresSession?) async -> LitresReach {
        var request = URLRequest(url: configuration.api.appending(path: "/foundation/api/users/me/arts"))

        request.url = request.url?.appending(queryItems: [ URLQueryItem(name: "limit", value: "1") ])
        apply(session, to: &request, host: .api)

        do {
            let (data, response) = try await self.session.data(for: request)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            let type = http?.value(forHTTPHeaderField: "Content-Type") ?? ""
            let server = http?.value(forHTTPHeaderField: "Server")
            let poweredBy = http?.value(forHTTPHeaderField: "Powered-By-Litres")
            let opening = String(decoding: data.prefix(220), as: UTF8.self)

            return LitresReach(
                status: status,
                isService: poweredBy != nil || type.contains("application/json"),
                isGuarded: Self.isGuarded(server: server, status: status, opening: opening),
                isSignedIn: status == 200 && poweredBy != nil,
                server: server,
                opening: opening
            )
        } catch {
            return LitresReach(
                status: 0,
                isService: false,
                isGuarded: false,
                isSignedIn: false,
                server: nil,
                opening: error.localizedDescription
            )
        }
    }

    /// The guard names itself in the server header, and answers a client it doubts with a page rather
    /// than with an answer.
    private static func isGuarded(server: String?, status: Int, opening: String) -> Bool {
        if server?.lowercased().contains("ddos-guard") == true { return true }
        if status == 403, opening.contains("<") { return true }

        return opening.localizedCaseInsensitiveContains("ddos-guard")
    }

    // MARK: - The reader's own library

    /// One page of the reader's books, and where the next one stands.
    ///
    /// The first page is asked for by hand; every page after it is the address the service gave, used
    /// exactly as it came.
    public func library(at page: URL? = nil, as session: LitresSession) async throws -> LitresLibraryPage {
        let url =
            page
            ?? configuration.api
            .appending(path: Self.libraryPath)
            .appending(queryItems: [ URLQueryItem(name: "limit", value: "\(Self.pageSize)") ])
        let payload: LitresLibraryPayload = try await get(url, as: session)

        return LitresLibraryPage(
            arts: payload.data,
            next: Self.next(after: payload.pagination?.nextPage, api: configuration.api)
        )
    }

    /// Every page of it, walked to the end.
    public func wholeLibrary(as session: LitresSession) async throws -> [LitresArt] {
        var found: [LitresArt] = []
        var page: URL?

        // However long a library runs, it ends: the walk stops when the service offers no next page,
        // and the ceiling is here so an address that never changed cannot spin for ever.
        for _ in 0 ..< Self.pageLimit {
            let read = try await library(at: page, as: session)

            found.append(contentsOf: read.arts)

            guard let next = read.next, next != page else { return found }

            page = next
        }

        return found
    }

    /// The files the service will hand over for one work.
    public func files(of art: Int, as session: LitresSession) async throws -> [LitresFile] {
        let url = configuration.api.appending(path: "/foundation/api/arts/\(art)/files/grouped")
        let payload: LitresFilesPayload = try await get(url, as: session)

        return payload.data.flatMap(\.files)
    }

    /// Where a file stands, on the host that hands files out rather than the one that answers questions.
    public func downloadURL(art: Int, file: LitresFile) -> URL {
        configuration.site.appending(path: "/download_book/\(art)/\(file.id)/\(file.downloadName)")
    }

    /// Fetches a file, or says what stood in the way.
    public func download(art: Int, file: LitresFile, as session: LitresSession) async throws -> Data {
        var request = URLRequest(url: downloadURL(art: art, file: file))

        apply(session, to: &request, host: .site)
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        await pace.wait()

        let (data, response) = try await self.session.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0

        guard status != 401, status != 403 else { throw LitresError.unauthorised }
        guard status == 200 else { throw LitresError.service(status: status) }
        // A challenge comes back as a page with a status of two hundred, so what arrived has to be
        // read rather than trusted. Every format the service offers is a binary of some kind.
        guard !Self.looksLikeMarkup(data) else { throw LitresError.guarded }

        return data
    }

    /// How many books are asked for at a time, and how many pages will be walked before giving up.
    /// What the site's own build asks for. The service allows a hundred, and there is nothing to be
    /// won by asking for one: this runs once and is in no hurry.
    private static let pageSize = 24
    private static let pageLimit = 500

    static let libraryPath = "/foundation/api/users/me/arts"

    /// Where the next page stands, from the path the service reported.
    ///
    /// The path arrives under `/api/`, which the API itself does not answer on, so the prefix is
    /// corrected and nothing else is touched. The cursor in it is base64 and carries `+` and `=`:
    /// taking it apart only to put it back re-encodes it, and a bare `+` in a query is a space to the
    /// server, so the cursor would arrive meaning something else.
    static func next(after path: String?, api: URL) -> URL? {
        guard let path else { return nil }

        let corrected = path.hasPrefix("/api/") ? "/foundation" + path : path

        return URL(string: corrected, relativeTo: api)?.absoluteURL
    }

    private static func looksLikeMarkup(_ data: Data) -> Bool {
        let opening = String(decoding: data.prefix(120), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        return opening.hasPrefix("<")
    }

    // MARK: - Asking a question

    private func get<Payload: Decodable>(_ url: URL, as session: LitresSession) async throws -> Payload {
        var request = URLRequest(url: url)

        apply(session, to: &request, host: .api)
        await pace.wait()

        let (data, response) = try await self.session.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0

        guard status != 401, status != 403 else { throw LitresError.unauthorised }
        guard http?.value(forHTTPHeaderField: "Powered-By-Litres") != nil else { throw LitresError.guarded }
        guard status == 200 else { throw LitresError.service(status: status) }

        do {
            guard
                let payload = try JSONDecoder.litres.decode(LitresEnvelope<Payload>.self, from: data).payload
            else { throw LitresError.malformed("the answer carried no payload") }

            return payload
        } catch let error as LitresError {
            throw error
        } catch {
            throw LitresError.malformed(String(describing: error))
        }
    }

    // MARK: - Signing every request

    private enum Host {
        case api
        case site
    }

    /// Puts the session on a request the way the host it is going to expects it.
    private func apply(_ session: LitresSession?, to request: inout URLRequest, host: Host) {
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")

        if host == .api {
            request.setValue(configuration.appId, forHTTPHeaderField: "App-Id")
            request.setValue(configuration.site.host(), forHTTPHeaderField: "Client-Host")
            request.setValue(configuration.language, forHTTPHeaderField: "UI-Language-Code")
            request.setValue(configuration.currency, forHTTPHeaderField: "UI-Currency")
            request.setValue(configuration.site.absoluteString, forHTTPHeaderField: "Origin")
            request.setValue(configuration.site.absoluteString + "/", forHTTPHeaderField: "Referer")
        }

        guard let session else { return }

        if host == .api {
            request.setValue(session.sessionId, forHTTPHeaderField: "Session-Id")
            request.setValue(session.superSessionId, forHTTPHeaderField: "supersid")
        }

        // Both hosts take the jar. The API does not need it, and the guard in front of both does.
        let jar = session.cookies
            .filter { !$0.hasExpired }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")

        if !jar.isEmpty { request.setValue(jar, forHTTPHeaderField: "Cookie") }
    }
}
