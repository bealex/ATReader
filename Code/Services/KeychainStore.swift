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
        case userId
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
