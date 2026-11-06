import CryptoKit
import Foundation
import XCTest
@testable import TypeCarrierCore

/// Runs the Swift protocol implementation against the Rust core in memory, in both directions,
/// to prove the two speak the same bytes before the apps switch to the Rust core.
final class CarrierCoreInteropTests: XCTestCase {
    private let phoneKey = Curve25519.KeyAgreement.PrivateKey()
    private let macKey = Curve25519.KeyAgreement.PrivateKey()

    func testRustPublicKeyMatchesCryptoKit() throws {
        XCTAssertEqual(try publicKeyFor(staticPrivateKey: phoneKey.rawRepresentation), phoneKey.publicKey.rawRepresentation)
    }

    func testSwiftPhonePairsWithRustMacAndBothShowTheSameCode() throws {
        var phone = swiftPhone(.pair, remoteKey: nil)
        let mac = rustMac(trusted: [], pairingOpen: true)

        var link = Link()
        link.toRust += written(phone.start())
        let (phoneEvents, macEvents) = link.pump(swift: &phone, rust: mac)

        let swiftCode = phoneEvents.compactMap { if case .pairingCodeReady(let code, _) = $0 { code } else { nil } }.first
        let rustCode = macEvents.compactMap { if case .pairingCodeReady(let code, _) = $0 { code } else { nil } }.first
        XCTAssertNotNil(swiftCode)
        XCTAssertEqual(swiftCode, rustCode)

        link.toSwift += rustWritten(mac.confirmPairing())
        let (afterPhone, _) = link.pump(swift: &phone, rust: mac)
        XCTAssertTrue(phone.isEstablished)
        XCTAssertTrue(mac.isEstablished())
        let peer = afterPhone.compactMap { if case .established(let peer) = $0 { peer } else { nil } }.first
        XCTAssertEqual(peer?.publicKey, macKey.publicKey.rawRepresentation)
        XCTAssertEqual(peer?.info.deviceID, "mac-1")
        XCTAssertEqual(mac.peer()?.platform, .ios)
        XCTAssertEqual(mac.peer()?.deviceName, "iPhone")
    }

    func testSwiftPhoneReconnectsToRustMacAndEnvelopesFlowBothWays() throws {
        var phone = swiftPhone(.connect, remoteKey: macKey.publicKey.rawRepresentation)
        let mac = rustMac(trusted: [phoneKey.publicKey.rawRepresentation], pairingOpen: false)
        var link = Link()
        link.toRust += written(phone.start())
        _ = link.pump(swift: &phone, rust: mac)
        XCTAssertTrue(phone.isEstablished)
        XCTAssertTrue(mac.isEstablished())

        let payload = CarrierPayload(createdAt: Date(timeIntervalSince1970: 1_780_000_000), text: "你好，Rust")
        link.toRust += written(try phone.send(.text(payload)))
        let (_, macEvents) = link.pump(swift: &phone, rust: mac)
        let json = try XCTUnwrap(macEvents.compactMap { if case .received(let json) = $0 { json } else { nil } }.first)
        XCTAssertEqual(try CarrierCodec.decode(Data(json.utf8)), .text(payload))

        link.toSwift += rustWritten(try mac.sendEnvelope(envelopeJson: String(decoding: try CarrierCodec.encode(.ack(payload.id)), as: UTF8.self)))
        let (phoneEvents, _) = link.pump(swift: &phone, rust: mac)
        XCTAssertEqual(phoneEvents, [.received(.ack(payload.id))])
    }

    func testRustPhonePairsAndReconnectsWithSwiftMac() throws {
        var mac = swiftMac(trusted: [], pairingOpen: true)
        let phone = rustPhone(.pair, remoteKey: nil)
        var link = Link()
        link.toSwift += rustWritten(phone.start())
        let (macEvents, phoneEvents) = link.pump(swift: &mac, rust: phone)
        let swiftCode = macEvents.compactMap { if case .pairingCodeReady(let code, _) = $0 { code } else { nil } }.first
        let rustCode = phoneEvents.compactMap { if case .pairingCodeReady(let code, _) = $0 { code } else { nil } }.first
        XCTAssertNotNil(swiftCode)
        XCTAssertEqual(swiftCode, rustCode)

        link.toRust += written(mac.confirmPairing())
        _ = link.pump(swift: &mac, rust: phone)
        XCTAssertTrue(phone.isEstablished())
        XCTAssertEqual(phone.peer()?.publicKey, macKey.publicKey.rawRepresentation)

        // Reconnect with IK.
        var macAgain = swiftMac(trusted: [phoneKey.publicKey.rawRepresentation], pairingOpen: false)
        let phoneAgain = rustPhone(.connect, remoteKey: macKey.publicKey.rawRepresentation)
        var again = Link()
        again.toSwift += rustWritten(phoneAgain.start())
        let (established, _) = again.pump(swift: &macAgain, rust: phoneAgain)
        XCTAssertTrue(phoneAgain.isEstablished())
        XCTAssertTrue(macAgain.isEstablished)
        let platforms: [CarrierHello.Platform] = established.compactMap { event in
            guard case .established(let peer) = event else { return nil }
            return peer.hello.platform
        }
        XCTAssertEqual(platforms, [.android])
    }

    func testRustMacRefusesUnpairedSwiftPhone() throws {
        var phone = swiftPhone(.connect, remoteKey: macKey.publicKey.rawRepresentation)
        let mac = rustMac(trusted: [], pairingOpen: false)
        var link = Link()
        link.toRust += written(phone.start())
        let (phoneEvents, macEvents) = link.pump(swift: &phone, rust: mac)
        XCTAssertTrue(phoneEvents.contains(.closed(.notPaired)))
        XCTAssertTrue(macEvents.contains(.closed(reason: .notPaired)))
    }

    // MARK: - Fixtures

    private func swiftPhone(_ mode: CarrierHello.Mode, remoteKey: Data?) -> CarrierV2Session {
        CarrierV2Session(
            role: .initiator(mode, remoteStaticKey: remoteKey),
            identity: CarrierV2Identity(
                staticKey: phoneKey,
                info: CarrierV2DeviceInfo(deviceID: "phone-1", deviceName: "iPhone"),
                platform: .iOS,
                capabilities: [CarrierHello.capabilitySendText]
            )
        )
    }

    private func swiftMac(trusted: [Data], pairingOpen: Bool) -> CarrierV2Session {
        CarrierV2Session(
            role: .responder,
            identity: CarrierV2Identity(
                staticKey: macKey,
                info: CarrierV2DeviceInfo(deviceID: "mac-1", deviceName: "Mac"),
                platform: .macOS,
                capabilities: [CarrierHello.capabilityReceivePaste]
            ),
            isTrusted: { trusted.contains($0) },
            isPairingOpen: { pairingOpen }
        )
    }

    private func rustMac(trusted: [Data], pairingOpen: Bool) -> CoreSession {
        CoreSession(
            role: .responder,
            identity: CoreIdentity(staticPrivateKey: macKey.rawRepresentation, deviceId: "mac-1", deviceName: "Mac", platform: .macOs, capabilities: ["receive.paste"]),
            nowMs: 0,
            policy: Policy(trusted: trusted, pairingOpen: pairingOpen)
        )
    }

    private func rustPhone(_ mode: CoreHelloMode, remoteKey: Data?) -> CoreSession {
        CoreSession(
            role: .initiator(mode: mode, remoteStaticKey: remoteKey),
            identity: CoreIdentity(staticPrivateKey: phoneKey.rawRepresentation, deviceId: "phone-1", deviceName: "Pixel", platform: .android, capabilities: ["send.text"]),
            nowMs: 0,
            policy: nil
        )
    }

    private final class Policy: CoreResponderPolicy, @unchecked Sendable {
        let trusted: [Data]
        let pairingOpen: Bool
        init(trusted: [Data], pairingOpen: Bool) {
            self.trusted = trusted
            self.pairingOpen = pairingOpen
        }
        func isTrusted(publicKey: Data) -> Bool { trusted.contains(publicKey) }
        func isPairingOpen() -> Bool { pairingOpen }
    }

    /// Bytes in flight between one Swift session and one Rust session.
    private struct Link {
        var toRust = Data()
        var toSwift = Data()

        mutating func pump(swift: inout CarrierV2Session, rust: CoreSession) -> ([CarrierV2SessionEvent], [CoreSessionEvent]) {
            var swiftEvents: [CarrierV2SessionEvent] = []
            var rustEvents: [CoreSessionEvent] = []
            while !toRust.isEmpty || !toSwift.isEmpty {
                let fromRust = toRust.isEmpty ? [] : rust.receive(bytes: toRust, nowMs: 0)
                let fromSwift = toSwift.isEmpty ? [] : swift.receive(toSwift)
                toRust = written(fromSwift)
                toSwift = rustWritten(fromRust)
                rustEvents += fromRust.filter { if case .write = $0 { false } else { true } }
                swiftEvents += fromSwift.filter { if case .write = $0 { false } else { true } }
            }
            return (swiftEvents, rustEvents)
        }
    }
}

private func written(_ events: [CarrierV2SessionEvent]) -> Data {
    events.reduce(into: Data()) { data, event in
        if case .write(let bytes) = event { data.append(bytes) }
    }
}

private func rustWritten(_ events: [CoreSessionEvent]) -> Data {
    events.reduce(into: Data()) { data, event in
        if case .write(let bytes) = event { data.append(bytes) }
    }
}
