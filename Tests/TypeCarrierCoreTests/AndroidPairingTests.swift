import Foundation
import XCTest
@testable import TypeCarrierCore

final class AndroidPairingTests: XCTestCase {
    func testPairingCodeAcceptsExactlySixDigits() {
        XCTAssertTrue(AndroidPairingCode.isValid("123456"))
        XCTAssertFalse(AndroidPairingCode.isValid("12345"))
        XCTAssertFalse(AndroidPairingCode.isValid("1234567"))
        XCTAssertFalse(AndroidPairingCode.isValid("12A456"))
        XCTAssertFalse(AndroidPairingCode.isValid(" 123456 "))
    }

    func testPairingCodeGeneratesSixDigits() {
        let code = AndroidPairingCode.generate(randomNumber: { _ in 42 })

        XCTAssertEqual(code, "000042")
        XCTAssertTrue(AndroidPairingCode.isValid(code))
    }

    func testTrustTokenUsesUrlSafeBase64WithoutPadding() throws {
        let bytes = Data([0xFB, 0xFF, 0xEE, 0x00])

        let token = try AndroidTrustToken.generate(randomBytes: { count in
            XCTAssertEqual(count, 32)
            return bytes
        })

        XCTAssertEqual(token.rawValue, "-__uAA")
    }

    func testProofValidatesTokenAndChallenge() throws {
        let token = AndroidTrustToken(rawValue: "known-token")
        let challenge = Data("nonce".utf8)
        let proof = AndroidTrustToken.proof(token: token, challenge: challenge)

        XCTAssertTrue(AndroidTrustToken.verify(token: token, challenge: challenge, proof: proof))
        XCTAssertFalse(AndroidTrustToken.verify(token: token, challenge: Data("other".utf8), proof: proof))
        XCTAssertFalse(AndroidTrustToken.verify(token: AndroidTrustToken(rawValue: "other-token"), challenge: challenge, proof: proof))
    }
}
