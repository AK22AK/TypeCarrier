import CryptoKit
import Foundation
import Network
import XCTest
@testable import TypeCarrierCore

/// Runs real TCP over loopback to check the link wiring around `CarrierV2Session`.
@MainActor
final class CarrierV2LinkTests: XCTestCase {
    private let phoneKey = Curve25519.KeyAgreement.PrivateKey()
    private let macKey = Curve25519.KeyAgreement.PrivateKey()
    private var listener: NWListener?
    private var macLinks: [CarrierV2Link] = []

    override func tearDown() async throws {
        listener?.cancel()
        macLinks.forEach { $0.close() }
    }

    func testPairsThenReconnectsAndDeliversOverLoopback() async throws {
        var trusted: [Data] = []
        var macEvents: [CarrierV2Link.Event] = []
        let port = try await startMac(trusted: { trusted.contains($0) }, pairingOpen: true) { link, event in
            macEvents.append(event)
            if case .pairingCodeReady(_, let peer) = event {
                trusted.append(peer.publicKey)
                link.confirmPairing()
            }
        }

        // Pair.
        let paired = expectation(description: "phone paired")
        var phoneCode: String?
        var macPublicKey: Data?
        let pairing = makePhoneLink(port: port, mode: .pair, remoteKey: nil) { _, event in
            if case .pairingCodeReady(let code, _) = event { phoneCode = code }
            if case .established(let peer) = event {
                macPublicKey = peer.publicKey
                paired.fulfill()
            }
        }
        pairing.start()
        await fulfillment(of: [paired], timeout: 5)
        XCTAssertEqual(macPublicKey, macKey.publicKey.rawRepresentation)
        XCTAssertEqual(phoneCode, macEvents.compactMap { if case .pairingCodeReady(let code, _) = $0 { code } else { nil } }.first)
        pairing.close()

        // Reconnect with IK and send a message.
        let connected = expectation(description: "phone reconnected")
        let delivered = expectation(description: "mac received")
        var macReceived: [CarrierEnvelope] = []
        let payload = CarrierPayload(createdAt: Date(timeIntervalSince1970: 1_780_000_000), text: "hello over tcp")
        let reconnect = makePhoneLink(port: port, mode: .connect, remoteKey: macPublicKey) { link, event in
            if case .established = event {
                connected.fulfill()
                try? link.send(.text(payload))
            }
        }
        macEventHandler = { _, event in
            if case .received(let envelope) = event {
                macReceived.append(envelope)
                delivered.fulfill()
            }
        }
        reconnect.start()
        await fulfillment(of: [connected, delivered], timeout: 5)
        XCTAssertEqual(macReceived, [.text(payload)])
        reconnect.close()
    }

    func testUnpairedReconnectIsClosedWithNotPaired() async throws {
        let port = try await startMac(trusted: { _ in false }, pairingOpen: false) { _, _ in }
        let closed = expectation(description: "phone closed")
        var reason: CarrierV2CloseReason?
        let link = makePhoneLink(port: port, mode: .connect, remoteKey: macKey.publicKey.rawRepresentation) { _, event in
            if case .closed(let closeReason, _) = event {
                reason = closeReason
                closed.fulfill()
            }
        }
        link.start()
        await fulfillment(of: [closed], timeout: 5)
        XCTAssertEqual(reason, .notPaired)
    }

    func testConnectingToNothingFailsQuickly() async throws {
        let closed = expectation(description: "closed")
        let link = makePhoneLink(port: 1, mode: .connect, remoteKey: macKey.publicKey.rawRepresentation) { _, event in
            if case .closed = event { closed.fulfill() }
        }
        link.start()
        await fulfillment(of: [closed], timeout: 3)
    }

    // MARK: - Helpers

    private var macEventHandler: ((CarrierV2Link, CarrierV2Link.Event) -> Void)?

    private func startMac(
        trusted: @escaping (Data) -> Bool,
        pairingOpen: Bool,
        onEvent: @escaping (CarrierV2Link, CarrierV2Link.Event) -> Void
    ) async throws -> UInt16 {
        macEventHandler = onEvent
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        let listener = try NWListener(using: parameters, on: .any)
        self.listener = listener
        let identity = CarrierV2Identity(
            staticKey: macKey,
            info: CarrierV2DeviceInfo(deviceID: "mac-1", deviceName: "Mac"),
            platform: .macOS,
            capabilities: [CarrierHello.capabilityReceivePaste]
        )
        // The listener runs on the main queue; the handler only hops onto the main actor.
        nonisolated(unsafe) let accept: (NWConnection) -> Void = { [weak self] connection in
            guard let self else { return }
            let session = CarrierV2Session(role: .responder, identity: identity, isTrusted: trusted, isPairingOpen: { pairingOpen })
            let link = CarrierV2Link(connection: connection, session: session) { [weak self] link, event in
                self?.macEventHandler?(link, event)
            }
            self.macLinks.append(link)
            link.start()
        }
        listener.newConnectionHandler = { connection in
            MainActor.assumeIsolated { accept(connection) }
        }
        let ready = expectation(description: "listener ready")
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        listener.start(queue: .main)
        await fulfillment(of: [ready], timeout: 3)
        return try XCTUnwrap(listener.port?.rawValue)
    }

    private func makePhoneLink(
        port: UInt16,
        mode: CarrierHello.Mode,
        remoteKey: Data?,
        onEvent: @escaping (CarrierV2Link, CarrierV2Link.Event) -> Void
    ) -> CarrierV2Link {
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let session = CarrierV2Session(
            role: .initiator(mode, remoteStaticKey: remoteKey),
            identity: CarrierV2Identity(
                staticKey: phoneKey,
                info: CarrierV2DeviceInfo(deviceID: "phone-1", deviceName: "iPhone"),
                platform: .iOS,
                capabilities: [CarrierHello.capabilitySendText]
            )
        )
        return CarrierV2Link(connection: connection, session: session, onEvent: onEvent)
    }
}
