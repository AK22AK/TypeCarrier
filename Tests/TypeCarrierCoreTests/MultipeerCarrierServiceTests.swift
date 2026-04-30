import MultipeerConnectivity
import XCTest
@testable import TypeCarrierCore

@MainActor
final class MultipeerCarrierServiceTests: XCTestCase {
    func testSenderStopsSearchingAfterSearchTimeout() async throws {
        let service = MultipeerCarrierService(
            role: .sender,
            displayName: "iPhone",
            searchTimeout: .milliseconds(20)
        )

        service.startSearchingForTesting()
        XCTAssertEqual(service.connectionState, .searching)

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(service.connectionState, .idle)
    }

    func testSenderShowsReconnectingKnownPeerAfterConnectionTimeout() async throws {
        let service = MultipeerCarrierService(
            role: .sender,
            displayName: "iPhone",
            searchTimeout: .milliseconds(80),
            connectionTimeout: .milliseconds(20)
        )
        let peerID = MCPeerID(displayName: "MacBook Pro")
        let browser = MCNearbyServiceBrowser(
            peer: MCPeerID(displayName: "Test Browser"),
            serviceType: MultipeerCarrierService.serviceType
        )

        service.browser(browser, foundPeer: peerID, withDiscoveryInfo: nil)
        await Task.yield()
        XCTAssertEqual(service.connectionState, .connecting("MacBook Pro"))

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(service.connectionState, .reconnecting("MacBook Pro"))

        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(service.connectionState, .idle)
    }

    func testSenderRetriesKnownPeerAfterConnectionTimeoutWithoutNewDiscoveryEvent() async throws {
        let service = MultipeerCarrierService(
            role: .sender,
            displayName: "iPhone",
            searchTimeout: .milliseconds(160),
            connectionTimeout: .milliseconds(20),
            connectionRetryDelay: .milliseconds(10)
        )
        let peerID = MCPeerID(displayName: "MacBook Pro")
        let browser = MCNearbyServiceBrowser(
            peer: MCPeerID(displayName: "Test Browser"),
            serviceType: MultipeerCarrierService.serviceType
        )

        service.browser(browser, foundPeer: peerID, withDiscoveryInfo: nil)
        await Task.yield()

        try await Task.sleep(for: .milliseconds(45))

        let inviteCount = service.diagnostics.events.filter { $0.name == "browser.invitePeer" }.count
        XCTAssertGreaterThanOrEqual(inviteCount, 2)
    }

    func testSenderShowsReconnectingKnownPeerWhenCurrentConnectionAttemptFails() async {
        let service = MultipeerCarrierService(role: .sender, displayName: "iPhone")
        let peerID = MCPeerID(displayName: "MacBook Pro")
        let browser = MCNearbyServiceBrowser(
            peer: MCPeerID(displayName: "Test Browser"),
            serviceType: MultipeerCarrierService.serviceType
        )

        service.browser(browser, foundPeer: peerID, withDiscoveryInfo: nil)
        await Task.yield()

        XCTAssertEqual(service.connectionState, .connecting("MacBook Pro"))

        service.session(MCSession(peer: MCPeerID(displayName: "Test Session")), peer: peerID, didChange: .notConnected)
        await Task.yield()

        XCTAssertEqual(service.connectionState, .reconnecting("MacBook Pro"))
    }

    func testSenderShowsReconnectingKnownPeerAfterEstablishedConnectionDrops() async throws {
        let service = MultipeerCarrierService(
            role: .sender,
            displayName: "iPhone",
            searchTimeout: .milliseconds(20)
        )
        let peerID = MCPeerID(displayName: "MacBook Pro")

        service.session(MCSession(peer: MCPeerID(displayName: "Test Session")), peer: peerID, didChange: .connected)
        await Task.yield()

        service.session(MCSession(peer: MCPeerID(displayName: "Test Session")), peer: peerID, didChange: .notConnected)
        await Task.yield()

        XCTAssertEqual(service.connectionState, .reconnecting("MacBook Pro"))

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(service.connectionState, .idle)
    }

    func testSenderDiagnosticsRecordDiscoveryInvitationAndTimeout() async throws {
        let service = MultipeerCarrierService(
            role: .sender,
            displayName: "iPhone",
            searchTimeout: .milliseconds(80),
            connectionTimeout: .milliseconds(20)
        )
        let peerID = MCPeerID(displayName: "MacBook Pro")
        let browser = MCNearbyServiceBrowser(
            peer: MCPeerID(displayName: "Test Browser"),
            serviceType: MultipeerCarrierService.serviceType
        )

        service.browser(browser, foundPeer: peerID, withDiscoveryInfo: nil)
        await Task.yield()

        XCTAssertEqual(service.diagnostics.discoveredPeers, ["MacBook Pro"])
        XCTAssertEqual(service.diagnostics.invitedPeers, ["MacBook Pro"])
        XCTAssertTrue(service.diagnostics.events.contains { $0.name == "browser.foundPeer" && $0.peerName == "MacBook Pro" })
        XCTAssertTrue(service.diagnostics.events.contains { $0.name == "browser.invitePeer" && $0.peerName == "MacBook Pro" })

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(service.diagnostics.events.contains { $0.name == "connection.timeout" && $0.peerName == "MacBook Pro" })
        XCTAssertEqual(service.diagnostics.connectionState, .reconnecting("MacBook Pro"))
    }

    func testReceiverDiagnosticsRecordAcceptedInvitation() async {
        let service = MultipeerCarrierService(role: .receiver, displayName: "MacBook Pro")
        let peerID = MCPeerID(displayName: "iPhone")
        let advertiser = MCNearbyServiceAdvertiser(
            peer: MCPeerID(displayName: "Test Advertiser"),
            discoveryInfo: nil,
            serviceType: MultipeerCarrierService.serviceType
        )
        var accepted = false
        var sessionWasProvided = false

        service.advertiser(
            advertiser,
            didReceiveInvitationFromPeer: peerID,
            withContext: nil
        ) { shouldAccept, session in
            accepted = shouldAccept
            sessionWasProvided = session != nil
        }
        await Task.yield()

        XCTAssertTrue(accepted)
        XCTAssertTrue(sessionWasProvided)
        XCTAssertTrue(service.diagnostics.events.contains { $0.name == "advertiser.invitation.accepted" && $0.peerName == "iPhone" })
    }
}
