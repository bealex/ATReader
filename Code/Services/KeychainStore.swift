//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Foundation
import Security

/// The reader's session secrets, kept in the keychain rather than in user defaults.
enum KeychainStore {
    enum Secret: String, CaseIterable {
        case token
        /// When the service said the token stops working, so it can be refreshed before it does.
        case tokenExpiry
        case userId
        /// The signed-in reader, so a launch without a network still knows who is reading.
        case user
        /// Lets a returning reader skip the two-factor challenge on the next sign-in.
        case trustedCode
    }

    private static let service = Bundle.main.bundleIdentifier ?? "com.lonelybytes.atreader"

    static func string(for key: Secret) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else { return nil }

        return String(data: data, encoding: .utf8)
    }

    static func integer(for key: Secret) -> Int? {
        string(for: key).flatMap(Int.init)
    }

    static func date(for key: Secret) -> Date? {
        string(for: key).flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
    }

    static func value<Value: Decodable>(_ type: Value.Type, for key: Secret) -> Value? {
        guard let raw = string(for: key) else { return nil }

        return try? JSONDecoder().decode(Value.self, from: Data(raw.utf8))
    }

    static func store(_ value: String?, for key: Secret) {
        guard let value else { return remove(key) }

        let attributes = [ kSecValueData as String: Data(value.utf8) ]
        let status = SecItemUpdate(baseQuery(for: key) as CFDictionary, attributes as CFDictionary)

        guard status == errSecItemNotFound else { return }

        var insert = baseQuery(for: key)
        insert[kSecValueData as String] = Data(value.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(insert as CFDictionary, nil)
    }

    static func store(_ value: Int?, for key: Secret) {
        store(value.map(String.init), for: key)
    }

    static func store(_ value: Date?, for key: Secret) {
        store(value.map { String($0.timeIntervalSince1970) }, for: key)
    }

    static func store(value: (some Encodable)?, for key: Secret) {
        guard let value, let data = try? JSONEncoder().encode(value) else { return remove(key) }

        store(String(decoding: data, as: UTF8.self), for: key)
    }

    static func remove(_ key: Secret) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    static func removeAll() {
        Secret.allCases.forEach(remove)
    }

    private static func baseQuery(for key: Secret) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }
}
