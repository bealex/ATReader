//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import CommonCrypto
import CryptoKit
import Foundation
import Testing

@testable import AuthorToday

/// The fixtures below are generated nonsense — the service's own payloads never enter the repository.
struct ChapterDecryptorTests {
    private let certificate = "Zm9vYmFyYmF6cXV4Cg=="
    private let salt = "0123456789abcdef"

    @Test
    func roundTripsAGuestChapter() throws {
        let body = "<p>Lorem ipsum dolor sit amet.</p><p>Consectetur adipiscing elit.</p>"
        let key = "0123456789abcdef0123456789abcdef"
        let encoded = try encrypt(body, key: key, userId: nil)
        let decoded = try ChapterDecryptor.decrypt(
            text: encoded,
            key: key,
            userId: nil,
            salt: salt,
            certificate: certificate
        )

        #expect(decoded == body)
    }

    @Test
    func roundTripsASignedInChapter() throws {
        let body = "<p>Quux corge grault garply waldo.</p>"
        let key = "fedcba9876543210fedcba9876543210"
        let encoded = try encrypt(body, key: key, userId: 4242)
        let decoded = try ChapterDecryptor.decrypt(
            text: encoded,
            key: key,
            userId: 4242,
            salt: salt,
            certificate: certificate
        )

        #expect(decoded == body)
    }

    @Test
    func rejectsAKeyBoundToAnotherAccount() throws {
        let key = "00112233445566778899aabbccddeeff"
        let encoded = try encrypt("<p>Fred plugh xyzzy thud.</p>", key: key, userId: 1)
        let decoded = try? ChapterDecryptor.decrypt(
            text: encoded,
            key: key,
            userId: 2,
            salt: salt,
            certificate: certificate
        )

        #expect(decoded == nil)
    }

    @Test
    func rejectsPayloadThatIsNotBase64() {
        #expect(throws: AuthorTodayError.self) {
            try ChapterDecryptor.decrypt(
                text: "not base64 ***",
                key: "abc",
                userId: nil,
                salt: salt,
                certificate: certificate
            )
        }
    }

    @Test
    func hexadecimalIsUppercase() {
        #expect(ChapterDecryptor.hexadecimal([ 0x00, 0x0f, 0xa5, 0xff ] as [UInt8]) == "000FA5FF")
    }

    // Mirrors the service side of the envelope so the test exercises the real derivation.
    private func encrypt(_ body: String, key: String, userId: Int?) throws -> String {
        let account = userId.map(String.init) ?? "Guest"
        let secret = "\(String(key.reversed())):\(account):\(salt):\(certificate)"
        let derived = Insecure.MD5.hash(data: Data(secret.utf8))
        let material = Data(ChapterDecryptor.hexadecimal(derived).utf8.prefix(kCCKeySizeAES128))
        let plaintext = Data(body.utf8)

        var output = Data(count: plaintext.count + kCCBlockSizeAES128)
        var movedBytes = 0
        let outputCount = output.count

        let status = output.withUnsafeMutableBytes { outputBuffer in
            plaintext.withUnsafeBytes { dataBuffer in
                material.withUnsafeBytes { keyBuffer in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
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

        #expect(status == kCCSuccess)
        output.removeSubrange(movedBytes...)
        return output.base64EncodedString()
    }
}

struct ChapterHTMLTests {
    @Test
    func splitsParagraphsAndDropsMarkup() {
        let html = "<p>Alpha <em>bravo</em> charlie.</p><p>Delta&nbsp;echo &mdash; foxtrot.</p>"
        let paragraphs = ChapterHTML.paragraphs(from: html)

        #expect(paragraphs.count == 2)
        #expect(paragraphs[0].text == "Alpha bravo charlie.")
        #expect(paragraphs[1].text == "Delta\u{00A0}echo — foxtrot.")
    }

    @Test
    func detectsCenteredParagraphs() {
        let html = "<p style=\"text-align: center;\">Golf hotel</p><p>India juliett</p>"
        let paragraphs = ChapterHTML.paragraphs(from: html)

        #expect(paragraphs[0].isCentered)
        #expect(!paragraphs[1].isCentered)
    }

    @Test
    func turnsLineBreaksIntoNewlines() {
        let paragraphs = ChapterHTML.paragraphs(from: "<p>Kilo<br>Lima</p>")

        #expect(paragraphs.count == 1)
        #expect(paragraphs[0].text == "Kilo\nLima")
    }

    @Test
    func fallsBackToBareText() {
        let paragraphs = ChapterHTML.paragraphs(from: "Mike november oscar")

        #expect(paragraphs.count == 1)
        #expect(paragraphs[0].text == "Mike november oscar")
    }

    @Test
    func skipsEmptyParagraphs() {
        let paragraphs = ChapterHTML.paragraphs(from: "<p></p><p>   </p><p>Papa</p>")

        #expect(paragraphs.count == 1)
        #expect(paragraphs[0].text == "Papa")
    }
}
