import CryptoKit
import Foundation
import XCTest
@testable import TypeCarrierCore

final class CarrierV2SessionTests: XCTestCase {
    private let phoneKey = Curve25519.KeyAgreement.PrivateKey()
    private let macKey = Curve25519.KeyAgreement.PrivateKey()

    func testPairingShowsTheSameCodeOnBothSidesAndEstablishesAfterConfirmation() throws {
        var phone = makePhone(.pair, remoteKey: nil)
        var mac = makeMac(pairingOpen: true)

        let (phoneEvents, macEvents) = pump(&phone, &mac, initial: phone.start())

        let phoneCode = try XCTUnwrap(pairingCode(in: phoneEvents))
        let macCode = try XCTUnwrap(pairingCode(in: macEvents))
        XCTAssertEqual(phoneCode, macCode)
        XCTAssertEqual(phoneCode.count, 6)
        XCTAssertFalse(phone.isEstablished)
        XCTAssertFalse(mac.isEstablished)
        XCTAssertEqual(mac.peer?.info.deviceName, "iPhone")
        XCTAssertEqual(mac.peer?.publicKey, phoneKey.publicKey.rawRepresentation)
        XCTAssertEqual(mac.peer?.platform, .iOS)

        let (afterPhone, afterMac) = pump(&phone, &mac, initial: [], macFirst: mac.confirmPairing())

        XCTAssertTrue(phone.isEstablished)
        XCTAssertTrue(mac.isEstablished)
        XCTAssertEqual(establishedPeer(in: afterPhone)?.publicKey, macKey.publicKey.rawRepresentation)
        XCTAssertEqual(establishedPeer(in: afterPhone)?.info.deviceName, "Mac")
        XCTAssertNotNil(establishedPeer(in: afterMac))
    }

    func testRejectedPairingClosesBothSides() {
        var phone = makePhone(.pair, remoteKey: nil)
        var mac = makeMac(pairingOpen: true)
        _ = pump(&phone, &mac, initial: phone.start())

        let (phoneEvents, _) = pump(&phone, &mac, initial: [], macFirst: mac.rejectPairing())

        XCTAssertTrue(phoneEvents.contains(.closed(.pairingRejected)))
        XCTAssertTrue(phone.isClosed)
        XCTAssertTrue(mac.isClosed)
    }

    func testPairingIsRefusedWhenTheReceiverHasNotOpenedIt() {
        var phone = makePhone(.pair, remoteKey: nil)
        var mac = makeMac(pairingOpen: false)

        let (phoneEvents, macEvents) = pump(&phone, &mac, initial: phone.start())

        XCTAssertTrue(phoneEvents.contains(.closed(.pairingNotOpen)))
        XCTAssertTrue(macEvents.contains(.closed(.pairingNotOpen)))
    }

    func testPairedReconnectEstablishesInOneRoundTripAndCarriesEnvelopesBothWays() throws {
        var phone = makePhone(.connect, remoteKey: macKey.publicKey.rawRepresentation)
        var mac = makeMac(trusted: [phoneKey.publicKey.rawRepresentation])

        let (phoneEvents, macEvents) = pump(&phone, &mac, initial: phone.start())

        XCTAssertEqual(establishedPeer(in: macEvents)?.info.deviceID, "phone-1")
        XCTAssertEqual(establishedPeer(in: phoneEvents)?.info.deviceID, "mac-1")

        // Whole seconds: envelopes encode dates as ISO 8601 without fractions.
        let payload = CarrierPayload(createdAt: Date(timeIntervalSince1970: 1_780_000_000), text: "你好，Mac")
        let (_, received) = pump(&phone, &mac, initial: try phone.send(.text(payload)))
        XCTAssertEqual(received, [.received(.text(payload))])

        let (receipt, _) = pump(&phone, &mac, initial: [], macFirst: try mac.send(.ack(payload.id)))
        XCTAssertEqual(receipt, [.received(.ack(payload.id))])
    }

    func testReconnectFromUnpairedDeviceIsRefused() {
        var phone = makePhone(.connect, remoteKey: macKey.publicKey.rawRepresentation)
        var mac = makeMac(trusted: [])

        let (phoneEvents, macEvents) = pump(&phone, &mac, initial: phone.start())

        XCTAssertTrue(macEvents.contains(.closed(.notPaired)))
        XCTAssertTrue(phoneEvents.contains(.closed(.notPaired)))
    }

    func testReconnectToAReceiverWhoseKeyChangedFailsTheHandshake() {
        var phone = makePhone(.connect, remoteKey: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation)
        var mac = makeMac(trusted: [phoneKey.publicKey.rawRepresentation])

        let (phoneEvents, macEvents) = pump(&phone, &mac, initial: phone.start())

        XCTAssertTrue(macEvents.contains(.closed(.handshakeFailed)))
        XCTAssertTrue(phoneEvents.contains(.closed(.handshakeFailed)))
        XCTAssertFalse(phone.isEstablished)
    }

    func testIncompatibleVersionsCloseWithUnsupportedVersion() throws {
        var mac = makeMac(trusted: [])
        let futureHello = Data(#"{"capabilities":[],"minProto":9,"mode":"connect","platform":"windows","proto":9}"#.utf8)

        let events = mac.receive(try CarrierWireFrame.encode(futureHello))

        XCTAssertEqual(events.last, .closed(.unsupportedVersion))
    }

    func testFramesSplitAcrossReadsAreReassembled() throws {
        var phone = makePhone(.connect, remoteKey: macKey.publicKey.rawRepresentation)
        var mac = makeMac(trusted: [phoneKey.publicKey.rawRepresentation])
        var toMac = Data(written(phone.start()))
        var macEvents: [CarrierV2SessionEvent] = []
        var phoneEvents: [CarrierV2SessionEvent] = []

        for _ in 0..<4 {
            for byte in toMac { macEvents += mac.receive(Data([byte])) }
            toMac = Data()
            for byte in written(macEvents) { phoneEvents += phone.receive(Data([byte])) }
            toMac = written(phoneEvents)
            macEvents.removeAll { if case .write = $0 { return true } else { return false } }
            phoneEvents.removeAll { if case .write = $0 { return true } else { return false } }
        }

        XCTAssertTrue(phone.isEstablished)
        XCTAssertTrue(mac.isEstablished)
    }

    func testHeartbeatPingsWhenIdleAndClosesAfterSilence() {
        var phone = makePhone(.connect, remoteKey: macKey.publicKey.rawRepresentation)
        var mac = makeMac(trusted: [phoneKey.publicKey.rawRepresentation])
        let start = Date()
        _ = pump(&phone, &mac, initial: phone.start(), now: start)

        XCTAssertTrue(phone.tick(now: start.addingTimeInterval(5)).isEmpty)
        let ping = phone.tick(now: start.addingTimeInterval(CarrierV2Session.pingInterval))
        XCTAssertEqual(ping.count, 1)
        let pong = mac.receive(written(ping), now: start.addingTimeInterval(CarrierV2Session.pingInterval))
        XCTAssertEqual(pong.count, 1)
        XCTAssertTrue(phone.receive(written(pong), now: start.addingTimeInterval(11)).isEmpty)

        let silent = phone.tick(now: start.addingTimeInterval(11 + CarrierV2Session.peerSilenceTimeout))
        XCTAssertEqual(silent.last, .closed(.heartbeatTimeout))
    }

    func testTamperedEstablishedFrameClosesTheSession() throws {
        var phone = makePhone(.connect, remoteKey: macKey.publicKey.rawRepresentation)
        var mac = makeMac(trusted: [phoneKey.publicKey.rawRepresentation])
        _ = pump(&phone, &mac, initial: phone.start())

        var frame = written(try phone.send(.text(CarrierPayload(text: "x"))))
        frame[frame.count - 1] ^= 0xFF

        XCTAssertEqual(mac.receive(frame).last, .closed(.handshakeFailed))
    }

    // MARK: - Helpers

    private func makePhone(_ mode: CarrierHello.Mode, remoteKey: Data?) -> CarrierV2Session {
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

    private func makeMac(trusted: [Data] = [], pairingOpen: Bool = false) -> CarrierV2Session {
        CarrierV2Session(
            role: .responder,
            identity: CarrierV2Identity(
                staticKey: macKey,
                info: CarrierV2DeviceInfo(deviceID: "mac-1", deviceName: "Mac"),
                platform: .macOS,
                capabilities: [CarrierHello.capabilityReceivePaste, CarrierHello.capabilityReceipt]
            ),
            isTrusted: { trusted.contains($0) },
            isPairingOpen: { pairingOpen }
        )
    }

    /// Delivers writes back and forth until both sides go quiet. Returns the non-write events each side produced.
    private func pump(
        _ phone: inout CarrierV2Session,
        _ mac: inout CarrierV2Session,
        initial: [CarrierV2SessionEvent],
        macFirst: [CarrierV2SessionEvent] = [],
        now: Date = Date()
    ) -> (phone: [CarrierV2SessionEvent], mac: [CarrierV2SessionEvent]) {
        var phoneEvents = initial.filter { !$0.isWrite }
        var macEvents = macFirst.filter { !$0.isWrite }
        var toMac = written(initial)
        var toPhone = written(macFirst)
        while !toMac.isEmpty || !toPhone.isEmpty {
            let fromMac = toMac.isEmpty ? [] : mac.receive(toMac, now: now)
            let fromPhone = toPhone.isEmpty ? [] : phone.receive(toPhone, now: now)
            macEvents += fromMac.filter { !$0.isWrite }
            phoneEvents += fromPhone.filter { !$0.isWrite }
            toPhone = written(fromMac)
            toMac = written(fromPhone)
        }
        return (phoneEvents, macEvents)
    }

    private func written(_ events: [CarrierV2SessionEvent]) -> Data {
        events.reduce(into: Data()) { data, event in
            if case .write(let bytes) = event { data.append(bytes) }
        }
    }

    private func pairingCode(in events: [CarrierV2SessionEvent]) -> String? {
        for case .pairingCodeReady(let code, _) in events { return code }
        return nil
    }

    private func establishedPeer(in events: [CarrierV2SessionEvent]) -> CarrierV2Peer? {
        for case .established(let peer) in events { return peer }
        return nil
    }
}

private extension CarrierV2SessionEvent {
    var isWrite: Bool {
        if case .write = self { return true }
        return false
    }
}
