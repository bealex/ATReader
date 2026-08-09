//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import CommonCrypto
import CryptoKit
import Foundation

/// Undoes the envelope the service wraps every chapter body in.
///
/// A chapter arrives as base64 of an AES-128-CBC ciphertext. The key is derived from the per-chapter `key`
/// field, the reader's account id, a fixed salt and the client certificate — so the same chapter decrypts
/// differently for each account.
///
/// The salt and certificate are configuration, not constants of this package. See `.env.example`.
enum ChapterDecryptor {
    /// Both `salt` and `certificate` are supplied by the caller — this package ships neither.
    static func decrypt(
        text: String,
        key: String,
        userId: Int?,
        salt: String,
        certificate: String
    ) throws -> String {
        guard !salt.isEmpty, !certificate.isEmpty else { throw AuthorTodayError.notConfigured }
        guard let ciphertext = Data(base64Encoded: text) else { throw AuthorTodayError.decryption }

        let account = userId.map(String.init) ?? "Guest"
        let secret = "\(String(key.reversed())):\(account):\(salt):\(certificate)"
        let derived = Insecure.MD5.hash(data: Data(secret.utf8))
        let material = Data(hexadecimal(derived).utf8.prefix(kCCKeySizeAES128))
        let plaintext = try decryptAES128CBC(ciphertext, key: material)

        guard let body = String(data: plaintext, encoding: .utf8) else { throw AuthorTodayError.decryption }

        return body
    }

    /// The service uses the key material as its own initialisation vector.
    private static func decryptAES128CBC(_ data: Data, key: Data) throws -> Data {
        var output = Data(count: data.count + kCCBlockSizeAES128)
        var movedBytes = 0
        let outputCount = output.count

        let status = output.withUnsafeMutableBytes { outputBuffer in
            data.withUnsafeBytes { dataBuffer in
                key.withUnsafeBytes { keyBuffer in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyBuffer.baseAddress,
                        keyBuffer.count,
                        keyBuffer.baseAddress,
                        dataBuffer.baseAddress,
                        dataBuffer.count,
                        outputBuffer.baseAddress,
                        outputCount,
                        &movedBytes
                    )
                }
            }
        }

        guard status == kCCSuccess else { throw AuthorTodayError.decryption }

        output.removeSubrange(movedBytes...)
        return output
    }

    /// Uppercase hex, matching the representation the service hashes on its side.
    static func hexadecimal(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }
}
