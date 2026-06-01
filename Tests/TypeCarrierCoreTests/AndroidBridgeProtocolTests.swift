import Foundation
import XCTest
@testable import TypeCarrierCore

final class AndroidBridgeProtocolTests: XCTestCase {
    func testHandshakeRoundTripsPairingAttempt() throws {
        let handshake = AndroidBridgeHandshake(
            version: 1,
            deviceID: "android-123",
            deviceName: "Pixel",
            pairingCode: "123456",
            tokenProof: nil,
            challenge: "nonce"
        )

        let decoded = try JSONDecoder().decode(
            AndroidBridgeHandshake.self,
            from: JSONEncoder().encode(handshake)
        )

        XCTAssertEqual(decoded, handshake)
        XCTAssertTrue(decoded.isPairingAttempt)
        XCTAssertFalse(decoded.isTokenAttempt)
    }

    func testHandshakeRoundTripsTokenAttempt() throws {
        let handshake = AndroidBridgeHandshake(
            version: 1,
            deviceID: "android-123",
            deviceName: "Pixel",
            pairingCode: nil,
            tokenProof: "proof",
            challenge: "nonce"
        )

        XCTAssertFalse(handshake.isPairingAttempt)
        XCTAssertTrue(handshake.isTokenAttempt)
    }

    func testBridgeResponseRoundTripsStatusAndTrustToken() throws {
        let response = AndroidBridgeResponse(
            status: .accepted,
            message: "paired",
            trustToken: "token"
        )

        let decoded = try JSONDecoder().decode(
            AndroidBridgeResponse.self,
            from: JSONEncoder().encode(response)
        )

        XCTAssertEqual(decoded, response)
    }

    func testBridgeResponseBusyDoesNotIncludeTrustToken() {
        let response = AndroidBridgeResponse.busy("Mac is already serving another device.")

        XCTAssertEqual(response.status, .busy)
        XCTAssertEqual(response.message, "Mac is already serving another device.")
        XCTAssertNil(response.trustToken)
    }

    func testActiveSenderGateAllowsOneDeviceAtATime() {
        var gate = AndroidBridgeActiveSenderGate()

        XCTAssertTrue(gate.claim(deviceID: "android-a"))
        XCTAssertTrue(gate.claim(deviceID: "android-a"))
        XCTAssertFalse(gate.claim(deviceID: "android-b"))

        gate.release(deviceID: "android-a")

        XCTAssertTrue(gate.claim(deviceID: "android-b"))
    }
}
