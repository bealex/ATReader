//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation

/// One reply from the service, described without the session that asked for it.
///
/// Carries cookie names but never their values, and the opening of the body only, so it can be written
/// into a trail a reader sends off the device.
public struct LitresExchange: Sendable, Equatable {
    public var url: URL?
    /// Zero where no reply arrived at all.
    public var status: Int
    public var server: String?
    public var contentType: String?
    public var isPoweredByLitres: Bool
    /// The first bytes of the body, as text.
    public var opening: String
    /// Names of the cookies the request carried.
    public var sentCookieNames: [String]
    /// True where the request carried the session as headers.
    public var sentSessionHeaders: Bool
    /// What stopped the request, where it never got a reply.
    public var failure: String?

    public init(
        url: URL? = nil,
        status: Int,
        server: String? = nil,
        contentType: String? = nil,
        isPoweredByLitres: Bool = false,
        opening: String = "",
        sentCookieNames: [String] = [],
        sentSessionHeaders: Bool = false,
        failure: String? = nil
    ) {
        self.url = url
        self.status = status
        self.server = server
        self.contentType = contentType
        self.isPoweredByLitres = isPoweredByLitres
        self.opening = opening
        self.sentCookieNames = sentCookieNames
        self.sentSessionHeaders = sentSessionHeaders
        self.failure = failure
    }

    init(_ response: HTTPURLResponse?, data: Data) {
        self.init(
            url: response?.url,
            status: response?.statusCode ?? 0,
            server: response?.value(forHTTPHeaderField: "Server"),
            contentType: response?.value(forHTTPHeaderField: "Content-Type"),
            isPoweredByLitres: response?.value(forHTTPHeaderField: "Powered-By-Litres") != nil,
            opening: String(decoding: data.prefix(Self.openingLength), as: UTF8.self)
        )
    }

    /// True where the body is a page rather than data.
    public var isMarkup: Bool { opening.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") }

    static let openingLength = 300
}
