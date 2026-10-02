import MultipeerConnectivity
import XCTest
@testable import TypeCarrierCore

@MainActor
final class MultiDeviceRoutingTests: XCTestCase {
    private func connect(_ service: MultipeerCarrierService, name: String, id: String, variant: String = "release") -> MCPeerID {
        let peer = MCPeerID(displayName: name)
        service.simulateFoundPeerForTesting(peer, discoveryInfo: ["macID": id, "appVariant": variant])
        service.simulateSessionStateForTesting(.connected, peerID: peer)
        return peer
    }

    func testOnePhoneConnectsTwoSameNamedMacsAndSendsOnlyToSelectedMac() throws {
        let phone = MultipeerCarrierService(role: .sender, displayName: "Phone")
        let a = connect(phone, name: "Mac", id: "A")
        let b = connect(phone, name: "Mac", id: "B")
        XCTAssertEqual(phone.connectedPeers.count, 2)
        var destinations: [MCPeerID] = []
        phone.sendForTesting = { _, peers in destinations += peers }

        XCTAssertThrowsError(try phone.send(.text(CarrierPayload(text: "No implicit target")))) {
            XCTAssertEqual($0 as? CarrierServiceError, .targetRequired)
        }
        try phone.send(.text(CarrierPayload(text: "A only")), to: phone.peerIdentity(for: a).id)
        XCTAssertEqual(destinations, [a])
        XCTAssertFalse(destinations.contains(b))
    }

    func testDisconnectAndDiscoveryLossDoNotInterruptOtherConnections() throws {
        let phone = MultipeerCarrierService(role: .sender, displayName: "Phone")
        let a = connect(phone, name: "Mac", id: "A")
        let b = connect(phone, name: "Mac", id: "B")
        phone.simulateLostPeerForTesting(b)
        XCTAssertEqual(phone.connectedPeers.count, 2, "Bonjour loss is not a transport disconnect")
        phone.simulateSessionStateForTesting(.notConnected, peerID: a)
        XCTAssertEqual(phone.connectedPeers.map(\.id), [phone.peerIdentity(for: b).id])
        XCTAssertTrue(phone.connectionState.isConnected)
        var destinations: [MCPeerID] = []
        phone.sendForTesting = { _, peers in destinations += peers }
        try phone.send(.text(CarrierPayload(text: "B stays online")), to: phone.peerIdentity(for: b).id)
        XCTAssertEqual(destinations, [b])
        XCTAssertThrowsError(try phone.send(.text(CarrierPayload(text: "A offline")), to: phone.peerIdentity(for: a).id))
    }

    func testDebugAndReleaseOnSameMacAreSeparateTargets() {
        let phone = MultipeerCarrierService(role: .sender, displayName: "Phone")
        let release = connect(phone, name: "Mac", id: "sameMac", variant: "release")
        let debug = connect(phone, name: "Mac", id: "sameMac", variant: "debug")
        XCTAssertNotEqual(phone.peerIdentity(for: release).id, phone.peerIdentity(for: debug).id)
        XCTAssertEqual(phone.connectedPeers.count, 2)
    }

    func testTwoSameNamedPhonesUseDistinctSessionsAndMacRepliesOnlyToSource() async throws {
        let mac = MultipeerCarrierService(role: .receiver, displayName: "Mac")
        let phones = [MCPeerID(displayName: "Phone"), MCPeerID(displayName: "Phone")]
        var sessions: [MCSession] = []
        for (index, phone) in phones.enumerated() {
            let context = try JSONEncoder().encode(CarrierDeviceIdentity(displayName: "Phone", deviceID: "phone-\(index)"))
            mac.simulateInvitationForTesting(from: phone, context: context) { accepted, session in
                XCTAssertTrue(accepted)
                if let session { sessions.append(session) }
            }
        }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(sessions.count, 2)
        if sessions.count == 2 { XCTAssertFalse(sessions[0] === sessions[1]) }
        for phone in phones { mac.simulateSessionStateForTesting(.connected, peerID: phone) }
        XCTAssertEqual(mac.connectedPeers.count, 2)
        XCTAssertNotEqual(mac.peerIdentity(for: phones[0]).id, mac.peerIdentity(for: phones[1]).id)
        var destinations: [MCPeerID] = []
        mac.sendForTesting = { _, peers in destinations += peers }
        try mac.send(.ack(UUID()), to: mac.peerIdentity(for: phones[0]).id)
        XCTAssertEqual(destinations, [phones[0]])
        mac.simulateSessionStateForTesting(.notConnected, peerID: phones[0])
        XCTAssertEqual(mac.connectedPeers.count, 1)
        XCTAssertTrue(mac.connectionState.isConnected)
    }

    func testLegacySameNamedPeersRemainDistinctWithoutStableIDs() {
        let mac = MultipeerCarrierService(role: .receiver, displayName: "Mac")
        let a = MCPeerID(displayName: "Phone")
        let b = MCPeerID(displayName: "Phone")
        mac.simulateSessionStateForTesting(.connected, peerID: a)
        mac.simulateSessionStateForTesting(.connected, peerID: b)
        XCTAssertNotEqual(mac.peerIdentity(for: a).id, mac.peerIdentity(for: b).id)
        XCTAssertEqual(mac.connectedPeers.count, 2)
    }

    func testTwoPhonesWithTwoMacTargetsNeverBroadcast() throws {
        for phoneIndex in 0..<2 {
            let phone = MultipeerCarrierService(role: .sender, displayName: "Phone \(phoneIndex)")
            let a = connect(phone, name: "Mac A", id: "A")
            let b = connect(phone, name: "Mac B", id: "B")
            let selected = phoneIndex == 0 ? a : b
            var destinations: [MCPeerID] = []
            phone.sendForTesting = { _, peers in destinations += peers }
            try phone.send(.text(CarrierPayload(text: "Text \(phoneIndex)")), to: phone.peerIdentity(for: selected).id)
            XCTAssertEqual(destinations, [selected])
        }
    }

    func testWrongMacReceiptDoesNotFinishSendAndCorrectReceiptDoes() {
        let wait = DeliveryConfirmationWait()
        let id = UUID()
        wait.begin(payloadID: id, targetID: "A") { XCTFail("Should confirm before timeout") }
        XCTAssertFalse(wait.confirm(payloadID: id, sourceID: "B"))
        XCTAssertFalse(wait.confirm(payloadID: UUID(), sourceID: "A"))
        XCTAssertFalse(wait.confirm(payloadID: id))
        XCTAssertTrue(wait.confirm(payloadID: id, sourceID: "A"))
        XCTAssertFalse(wait.confirm(payloadID: id, sourceID: "A"))
    }

    func testStaleSessionCallbacksCannotDisconnectReconnectedTarget() async throws {
        let phone = MultipeerCarrierService(role: .sender, displayName: "Phone")
        let a = connect(phone, name: "Mac A", id: "A")
        let b = connect(phone, name: "Mac B", id: "B")
        let staleSession = try XCTUnwrap(phone.sessionForTesting(peerID: a))
        phone.simulateSessionStateForTesting(.notConnected, peerID: a)
        phone.simulateSessionStateForTesting(.connected, peerID: a)
        phone.session(staleSession, peer: a, didChange: .notConnected)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(phone.connectedPeers.count, 2)
        XCTAssertTrue(phone.connectedPeers.contains { $0.id == phone.peerIdentity(for: b).id })
    }

    func testOnePeerConnectionTimeoutDoesNotResetConnectedMac() async throws {
        let phone = MultipeerCarrierService(role: .sender, displayName: "Phone", connectionTimeout: .milliseconds(20))
        let a = connect(phone, name: "Mac A", id: "A")
        let b = MCPeerID(displayName: "Mac B")
        phone.simulateFoundPeerForTesting(b, discoveryInfo: ["macID": "B"])
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(phone.connectedPeers.map(\.id), [phone.peerIdentity(for: a).id])
        XCTAssertTrue(phone.connectionState.isConnected)
    }

    func testUnrelatedPeerDataOnAnActiveSessionIsIgnored() async throws {
        let phone = MultipeerCarrierService(role: .sender, displayName: "Phone")
        let a = connect(phone, name: "Mac A", id: "A")
        let b = connect(phone, name: "Mac B", id: "B")
        let sessionA = try XCTUnwrap(phone.sessionForTesting(peerID: a))
        phone.session(sessionA, didReceive: try CarrierCodec.encode(.ack(UUID())), fromPeer: b)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(phone.lastReceivedEnvelope)
    }

    func testStaleAdvertiserCannotAcceptNewConnection() async {
        let mac = MultipeerCarrierService(role: .receiver, displayName: "Mac")
        let stale = MCNearbyServiceAdvertiser(peer: MCPeerID(displayName: "Old"), discoveryInfo: nil, serviceType: MultipeerCarrierService.serviceType)
        var accepted = true
        mac.advertiser(stale, didReceiveInvitationFromPeer: MCPeerID(displayName: "Phone"), withContext: nil) { accept, _ in accepted = accept }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(accepted)
        XCTAssertTrue(mac.connectedPeers.isEmpty)
    }

    func testReceiverDropsOnlyStuckInvitationAfterTimeout() async throws {
        let mac = MultipeerCarrierService(role: .receiver, displayName: "Mac", connectionTimeout: .milliseconds(20))
        let online = MCPeerID(displayName: "Online Phone")
        let stuck = MCPeerID(displayName: "Stuck Phone")
        mac.simulateSessionStateForTesting(.connected, peerID: online)
        mac.simulateInvitationForTesting(from: stuck) { accepted, _ in XCTAssertTrue(accepted) }
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertNil(mac.sessionForTesting(peerID: stuck))
        XCTAssertNotNil(mac.sessionForTesting(peerID: online))
        XCTAssertEqual(mac.connectedPeers.count, 1)
        XCTAssertTrue(mac.connectionState.isConnected)
    }
}
