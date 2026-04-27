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

    func testSenderReturnsToSearchingAfterConnectionTimeout() async throws {
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

        XCTAssertEqual(service.connectionState, .searching)

        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(service.connectionState, .idle)
    }

    func testSenderReturnsToSearchingWhenCurrentConnectionAttemptFails() async {
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

        XCTAssertEqual(service.connectionState, .searching)
    }

    func testSenderReturnsToSearchingAfterEstablishedConnectionDrops() async throws {
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

        XCTAssertEqual(service.connectionState, .searching)

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(service.connectionState, .idle)
    }
}
